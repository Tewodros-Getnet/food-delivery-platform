import { v4 as uuidv4 } from 'uuid';
import { query, withTransaction } from '../config/database';
import { Order, OrderItem, CartItem, OrderStatus } from '../models/order.model';
import { calculateDeliveryFee } from '../utils/haversine';
import { env } from '../config/env';
import * as chapaService from './chapa.service';
import { sendPushNotification } from './fcm.service';

export interface CreateOrderInput {
  customerId: string;
  restaurantId: string;
  deliveryAddressId: string;
  items: CartItem[];
}

export async function createOrder(input: CreateOrderInput): Promise<{ order: Order; paymentUrl: string }> {
  return withTransaction(async (client) => {
    // Validate all menu items are available and belong to the restaurant
    const itemIds = input.items.map((i) => i.menuItemId);
    const menuResult = await client.query(
      `SELECT * FROM menu_items WHERE id = ANY($1::uuid[]) AND restaurant_id = $2`,
      [itemIds, input.restaurantId]
    );

    if (menuResult.rowCount !== input.items.length) {
      const err = new Error('One or more menu items are unavailable or invalid') as Error & { statusCode: number };
      err.statusCode = 422;
      throw err;
    }

    const unavailable = menuResult.rows.filter((r: { available: boolean }) => !r.available);
    if (unavailable.length > 0) {
      const err = new Error('Some items are no longer available') as Error & { statusCode: number };
      err.statusCode = 422;
      throw err;
    }

    // Get restaurant and address coords for fee calculation
    const [rResult, aResult] = await Promise.all([
      client.query('SELECT latitude, longitude FROM restaurants WHERE id = $1', [input.restaurantId]),
      client.query('SELECT latitude, longitude FROM addresses WHERE id = $1', [input.deliveryAddressId]),
    ]);

    const r = rResult.rows[0] as { latitude: number; longitude: number };
    const a = aResult.rows[0] as { latitude: number; longitude: number };

    const delivery_fee = calculateDeliveryFee(
      r.latitude, r.longitude, a.latitude, a.longitude,
      env.DELIVERY_BASE_FEE, env.DELIVERY_RATE_PER_KM
    );

    // Calculate subtotal
    const menuMap = new Map(menuResult.rows.map((m: { id: string; price: number; name: string; image_url: string }) => [m.id, m]));
    let subtotal = 0;
    for (const item of input.items) {
      const menuItem = menuMap.get(item.menuItemId) as { price: number } | undefined;
      if (menuItem) subtotal += menuItem.price * item.quantity;
    }
    const total = subtotal + delivery_fee;

    const txRef = uuidv4();

    // Create order
    const orderResult = await client.query<Order>(
      `INSERT INTO orders (customer_id, restaurant_id, delivery_address_id, status, subtotal, delivery_fee, total, payment_reference)
       VALUES ($1,$2,$3,'pending_payment',$4,$5,$6,$7) RETURNING *`,
      [input.customerId, input.restaurantId, input.deliveryAddressId, subtotal, delivery_fee, total, txRef]
    );
    const order = orderResult.rows[0];

    // Insert order items
    for (const item of input.items) {
      const menuItem = menuMap.get(item.menuItemId) as { price: number; name: string; image_url: string } | undefined;
      if (menuItem) {
        await client.query(
          `INSERT INTO order_items (order_id, menu_item_id, quantity, unit_price, item_name, item_image_url)
           VALUES ($1,$2,$3,$4,$5,$6)`,
          [order.id, item.menuItemId, item.quantity, menuItem.price, menuItem.name, menuItem.image_url]
        );
      }
    }

    // Get customer email for Chapa
    const userResult = await client.query('SELECT email, display_name FROM users WHERE id = $1', [input.customerId]);
    const user = userResult.rows[0] as { email: string; display_name: string };

    // Initialize Chapa payment
    const chapaResponse = await chapaService.initializePayment({
      amount: total,
      currency: 'ETB',
      txRef,
      email: user.email,
      firstName: user.display_name || 'Customer',
    });

    return { order, paymentUrl: chapaResponse.data.checkout_url };
  });
}

export async function getOrderById(id: string): Promise<Order | null> {
  const result = await query<Order>('SELECT * FROM orders WHERE id = $1', [id]);
  return result.rows[0] ?? null;
}

export async function getOrderItems(orderId: string): Promise<OrderItem[]> {
  const result = await query<OrderItem>('SELECT * FROM order_items WHERE order_id = $1', [orderId]);
  return result.rows;
}

export async function getOrdersByUser(userId: string, role: string): Promise<Order[]> {
  let q: string;
  if (role === 'customer') {
    q = 'SELECT * FROM orders WHERE customer_id = $1 ORDER BY created_at DESC';
  } else if (role === 'restaurant') {
    const rResult = await query('SELECT id FROM restaurants WHERE owner_id = $1', [userId]);
    if (!rResult.rows[0]) return [];
    const restaurantId = (rResult.rows[0] as { id: string }).id;
    const result = await query<Order>('SELECT * FROM orders WHERE restaurant_id = $1 ORDER BY created_at DESC', [restaurantId]);
    return result.rows;
  } else if (role === 'rider') {
    q = 'SELECT * FROM orders WHERE rider_id = $1 ORDER BY created_at DESC';
  } else {
    q = 'SELECT * FROM orders ORDER BY created_at DESC';
  }
  const result = await query<Order>(q, [userId]);
  return result.rows;
}

export async function updateOrderStatus(
  orderId: string,
  status: OrderStatus,
  extra?: Partial<Order>
): Promise<Order | null> {
  const fields = ['status = $1', 'updated_at = NOW()'];
  const values: unknown[] = [status];
  let idx = 2;

  if (extra?.rider_id !== undefined) { fields.push(`rider_id = $${idx++}`); values.push(extra.rider_id); }
  if (extra?.payment_reference !== undefined) { fields.push(`payment_reference = $${idx++}`); values.push(extra.payment_reference); }
  if (extra?.payment_status !== undefined) { fields.push(`payment_status = $${idx++}`); values.push(extra.payment_status); }
  if (extra?.cancellation_reason !== undefined) { fields.push(`cancellation_reason = $${idx++}`); values.push(extra.cancellation_reason); }
  if (extra?.cancelled_at !== undefined) { fields.push(`cancelled_at = $${idx++}`); values.push(extra.cancelled_at); }
  if (extra?.estimated_prep_time_minutes !== undefined) { fields.push(`estimated_prep_time_minutes = $${idx++}`); values.push(extra.estimated_prep_time_minutes); }

  values.push(orderId);
  const result = await query<Order>(
    `UPDATE orders SET ${fields.join(', ')} WHERE id = $${idx} RETURNING *`,
    values
  );
  return result.rows[0] ?? null;
}

export async function handleWebhook(payload: string, signature: string): Promise<void> {
  if (!chapaService.verifyWebhookSignature(payload, signature)) {
    const err = new Error('Invalid webhook signature') as Error & { statusCode: number };
    err.statusCode = 401;
    throw err;
  }

  const data = JSON.parse(payload) as { tx_ref: string; status: string; amount: number };
  const { tx_ref, status, amount } = data;

  // Idempotency: check if already processed
  const existing = await query(
    `SELECT id, status FROM orders WHERE payment_reference = $1`,
    [tx_ref]
  );
  if (!existing.rows[0]) return;

  const order = existing.rows[0] as { id: string; status: string };
  if (order.status !== 'pending_payment') return; // Already processed

  if (status === 'success') {
    const confirmed = await updateOrderStatus(order.id, 'confirmed', {
      payment_status: 'paid',
      payment_reference: tx_ref,
    });
    // Notify restaurant owner
    if (confirmed) {
      const rResult = await query<{ owner_id: string }>(
        'SELECT owner_id FROM restaurants WHERE id = $1', [confirmed.restaurant_id]
      );
      if (rResult.rows[0]) {
        void sendPushNotification(rResult.rows[0].owner_id, 'New Order', 'You have a new order!', { orderId: confirmed.id });
      }
    }
  } else {
    await updateOrderStatus(order.id, 'payment_failed', { payment_status: 'failed' });
  }
}
