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

// Extended cart item that may carry selected modifiers from the Flutter app
export interface CartItemWithModifiers extends CartItem {
  selectedModifiers?: Array<{ group: string; option: string; price: number }>;
}

// ── Helper: read acceptance timeout from platform_config ─────────────────────
export async function getAcceptanceTimeoutSeconds(): Promise<number> {
  const result = await query<{ value: string }>(
    "SELECT value FROM platform_config WHERE key = 'order_acceptance_timeout_seconds'"
  );
  return parseInt(result.rows[0]?.value ?? '180', 10);
}

export async function createOrder(input: CreateOrderInput): Promise<{ order: Order; paymentUrl: string }> {
  return withTransaction(async (client) => {
    // Check email verification first — before any DB writes
    const userResult = await client.query('SELECT email, display_name, email_verified FROM users WHERE id = $1', [input.customerId]);
    const user = userResult.rows[0] as { email: string; display_name: string; email_verified: boolean };
    if (!user.email_verified) {
      const err = new Error('Please verify your email before placing an order') as Error & { statusCode: number };
      err.statusCode = 403;
      throw err;
    }

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

    const [rResult, aResult] = await Promise.all([
      client.query('SELECT latitude, longitude, is_open FROM restaurants WHERE id = $1', [input.restaurantId]),
      client.query('SELECT latitude, longitude FROM addresses WHERE id = $1', [input.deliveryAddressId]),
    ]);

    const r = rResult.rows[0] as { latitude: number; longitude: number; is_open: boolean };
    const a = aResult.rows[0] as { latitude: number; longitude: number };

    if (r.is_open === false) {
      const err = new Error('Restaurant is currently closed') as Error & { statusCode: number };
      err.statusCode = 422;
      throw err;
    }

    const delivery_fee = calculateDeliveryFee(
      r.latitude, r.longitude, a.latitude, a.longitude,
      env.DELIVERY_BASE_FEE, env.DELIVERY_RATE_PER_KM
    );

    const menuMap = new Map(menuResult.rows.map((m: { id: string; price: number; name: string; image_url: string }) => [m.id, m]));
    let subtotal = 0;
    for (const item of input.items) {
      const menuItem = menuMap.get(item.menuItemId) as { price: number } | undefined;
      if (menuItem) {
        const modifierExtra = ((item as CartItemWithModifiers).selectedModifiers ?? [])
          .reduce((sum, m) => sum + (m.price ?? 0), 0);
        subtotal += (menuItem.price + modifierExtra) * item.quantity;
      }
    }
    const total = subtotal + delivery_fee;
    const txRef = uuidv4();

    const orderResult = await client.query<Order>(
      `INSERT INTO orders (customer_id, restaurant_id, delivery_address_id, status, subtotal, delivery_fee, total, payment_reference)
       VALUES ($1,$2,$3,'pending_payment',$4,$5,$6,$7) RETURNING *`,
      [input.customerId, input.restaurantId, input.deliveryAddressId, subtotal, delivery_fee, total, txRef]
    );
    const order = orderResult.rows[0];

    for (const item of input.items) {
      const menuItem = menuMap.get(item.menuItemId) as { price: number; name: string; image_url: string } | undefined;
      if (menuItem) {
        const modifiers = (item as CartItemWithModifiers).selectedModifiers ?? [];
        const modifierExtra = modifiers.reduce((sum, m) => sum + (m.price ?? 0), 0);
        await client.query(
          `INSERT INTO order_items (order_id, menu_item_id, quantity, unit_price, item_name, item_image_url, selected_modifiers)
           VALUES ($1,$2,$3,$4,$5,$6,$7)`,
          [order.id, item.menuItemId, item.quantity, menuItem.price + modifierExtra,
           menuItem.name, menuItem.image_url, JSON.stringify(modifiers)]
        );
      }
    }

    // Only pass return_url if it's a valid http/https URL — Chapa rejects custom schemes
    const appBase = env.APP_DEEP_LINK_BASE || '';
    const returnUrl = appBase.startsWith('http')
      ? appBase + '/order/' + order.id + '/track'
      : undefined;

    const chapaResponse = await chapaService.initializePayment({
      amount: total,
      currency: 'ETB',
      txRef,
      email: user.email,
      firstName: user.display_name || 'Customer',
      returnUrl,
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
  let result;
  if (role === 'customer') {
    result = await query<Order>(
      `SELECT o.*,
              r.name as restaurant_name,
              (SELECT STRING_AGG(oi.item_name || ' x' || oi.quantity, ', ' ORDER BY oi.id)
               FROM order_items oi WHERE oi.order_id = o.id) as items_summary
       FROM orders o
       JOIN restaurants r ON r.id = o.restaurant_id
       WHERE o.customer_id = $1
       ORDER BY o.created_at DESC`,
      [userId]
    );
  } else if (role === 'restaurant') {
    const rResult = await query('SELECT id FROM restaurants WHERE owner_id = $1', [userId]);
    if (!rResult.rows[0]) return [];
    const restaurantId = (rResult.rows[0] as { id: string }).id;
    result = await query<Order>('SELECT * FROM orders WHERE restaurant_id = $1 ORDER BY created_at DESC', [restaurantId]);
  } else if (role === 'rider') {
    result = await query<Order>('SELECT * FROM orders WHERE rider_id = $1 ORDER BY created_at DESC', [userId]);
  } else {
    result = await query<Order>('SELECT * FROM orders ORDER BY created_at DESC', []);
  }
  return result.rows;
}

export async function updateOrderStatus(
  orderId: string,
  status: OrderStatus,
  extra?: Partial<Order & { acceptance_deadline: Date | null }>
): Promise<Order | null> {
  const fields: string[] = ['status = $1', 'updated_at = NOW()'];
  const values: unknown[] = [status];
  let idx = 2;

  if (extra?.rider_id !== undefined) {
    fields.push(`rider_id = $${idx++}`);
    values.push(extra.rider_id);
  }
  if (extra?.payment_reference !== undefined) {
    fields.push(`payment_reference = $${idx++}`);
    values.push(extra.payment_reference);
  }
  if (extra?.payment_status !== undefined) {
    fields.push(`payment_status = $${idx++}`);
    values.push(extra.payment_status);
  }
  if (extra?.cancellation_reason !== undefined) {
    fields.push(`cancellation_reason = $${idx++}`);
    values.push(extra.cancellation_reason);
  }
  if (extra?.cancelled_at !== undefined) {
    fields.push(`cancelled_at = $${idx++}`);
    values.push(extra.cancelled_at);
  }
  if (extra?.cancelled_by !== undefined) {
    fields.push(`cancelled_by = $${idx++}`);
    values.push(extra.cancelled_by);
  }
  if (extra?.estimated_prep_time_minutes !== undefined) {
    fields.push(`estimated_prep_time_minutes = $${idx++}`);
    values.push(extra.estimated_prep_time_minutes);
  }
  if (extra?.acceptance_deadline !== undefined) {
    fields.push(`acceptance_deadline = $${idx++}`);
    values.push(extra.acceptance_deadline);
  }

  values.push(orderId);
  const sql = `UPDATE orders SET ${fields.join(', ')} WHERE id = $${idx} RETURNING *`;
  const result = await query<Order>(sql, values);
  return result.rows[0] ?? null;
}

export async function handleWebhook(payload: string, signature: string): Promise<void> {
  if (!chapaService.verifyWebhookSignature(payload, signature)) {
    const err = new Error('Invalid webhook signature') as Error & { statusCode: number };
    err.statusCode = 401;
    throw err;
  }

  const data = JSON.parse(payload) as { tx_ref: string; status: string; amount: number };
  const { tx_ref, status } = data;

  const existing = await query(
    'SELECT id, status, customer_id FROM orders WHERE payment_reference = $1',
    [tx_ref]
  );
  if (!existing.rows[0]) return;

  const order = existing.rows[0] as { id: string; status: string; customer_id: string };
  if (order.status !== 'pending_payment') return;

  if (status === 'success') {
    // Transition to pending_acceptance (not confirmed) — restaurant must accept first
    const timeoutSeconds = await getAcceptanceTimeoutSeconds();
    const acceptanceDeadline = new Date(Date.now() + timeoutSeconds * 1000);

    const pending = await updateOrderStatus(order.id, 'pending_acceptance', {
      payment_status: 'paid',
      payment_reference: tx_ref,
      acceptance_deadline: acceptanceDeadline,
    });

    if (pending) {
      const rResult = await query<{ owner_id: string }>(
        'SELECT owner_id FROM restaurants WHERE id = $1', [pending.restaurant_id]
      );
      const { emitOrderStatusChanged, emitOrderAcceptanceRequest } = await import('./socket.service');

      if (rResult.rows[0]) {
        const ownerId = rResult.rows[0].owner_id;
        // Notify restaurant: FCM push + socket acceptance_request event
        void sendPushNotification(
          ownerId,
          'New Order',
          'You have a new order! Please accept or reject within 3 minutes.',
          { type: 'order_acceptance_request', orderId: pending.id }
        );
        emitOrderAcceptanceRequest(ownerId, pending);
      }
      // Notify customer: socket status_changed only
      emitOrderStatusChanged(pending, order.customer_id);
    }
  } else {
    const failed = await updateOrderStatus(order.id, 'payment_failed', { payment_status: 'failed' });
    if (failed) {
      const { emitOrderStatusChanged } = await import('./socket.service');
      emitOrderStatusChanged(failed, order.customer_id);
    }
  }
}

// ── Accept order (restaurant confirms they will fulfill it) ───────────────────
export async function acceptOrder(
  orderId: string,
  restaurantOwnerId: string,
  estimatedPrepMinutes?: number
): Promise<Order> {
  const order = await getOrderById(orderId);
  if (!order) {
    const err = new Error('Order not found') as Error & { statusCode: number };
    err.statusCode = 404;
    throw err;
  }

  // Verify ownership
  const rResult = await query<{ id: string }>(
    'SELECT id FROM restaurants WHERE owner_id = $1', [restaurantOwnerId]
  );
  if (!rResult.rows[0] || rResult.rows[0].id !== order.restaurant_id) {
    const err = new Error('Forbidden') as Error & { statusCode: number };
    err.statusCode = 403;
    throw err;
  }

  if (order.status !== 'pending_acceptance') {
    const err = new Error('Order is not awaiting acceptance') as Error & { statusCode: number };
    err.statusCode = 409;
    throw err;
  }

  const updated = await updateOrderStatus(orderId, 'confirmed', {
    estimated_prep_time_minutes: estimatedPrepMinutes,
  });
  if (!updated) {
    const err = new Error('Failed to update order') as Error & { statusCode: number };
    err.statusCode = 500;
    throw err;
  }

  const { emitOrderStatusChanged, emitToRestaurant } = await import('./socket.service');
  // Notify customer: FCM + socket
  void sendPushNotification(
    order.customer_id,
    'Order Accepted',
    'Your order has been accepted and is being prepared!',
    { type: 'order_accepted', orderId }
  );
  emitOrderStatusChanged(updated, order.customer_id);
  // Notify restaurant owner: socket
  emitToRestaurant(restaurantOwnerId, updated);

  return updated;
}

// ── Reject order (restaurant cannot fulfill it) ───────────────────────────────
export async function rejectOrder(
  orderId: string,
  restaurantOwnerId: string,
  reason: string
): Promise<Order> {
  const order = await getOrderById(orderId);
  if (!order) {
    const err = new Error('Order not found') as Error & { statusCode: number };
    err.statusCode = 404;
    throw err;
  }

  // Verify ownership
  const rResult = await query<{ id: string }>(
    'SELECT id FROM restaurants WHERE owner_id = $1', [restaurantOwnerId]
  );
  if (!rResult.rows[0] || rResult.rows[0].id !== order.restaurant_id) {
    const err = new Error('Forbidden') as Error & { statusCode: number };
    err.statusCode = 403;
    throw err;
  }

  if (order.status !== 'pending_acceptance') {
    const err = new Error('Order is not awaiting acceptance') as Error & { statusCode: number };
    err.statusCode = 409;
    throw err;
  }

  const updated = await updateOrderStatus(orderId, 'cancelled', {
    cancellation_reason: reason,
    cancelled_by: 'restaurant',
    cancelled_at: new Date(),
  });
  if (!updated) {
    const err = new Error('Failed to update order') as Error & { statusCode: number };
    err.statusCode = 500;
    throw err;
  }

  // Fire-and-forget refund
  const { initiateRefund } = await import('./refund.service');
  void initiateRefund(orderId);

  const { emitOrderStatusChanged, emitToRestaurant } = await import('./socket.service');
  // Notify customer: FCM + socket
  void sendPushNotification(
    order.customer_id,
    'Order Rejected',
    `Your order was rejected: ${reason}. A refund has been initiated.`,
    { type: 'order_rejected', orderId, reason }
  );
  emitOrderStatusChanged(updated, order.customer_id);
  // Notify restaurant owner: socket
  emitToRestaurant(restaurantOwnerId, updated);

  return updated;
}

// ── Called by rider.service when no rider is found after all retries ──────────
export async function cancelOrderNoRider(orderId: string): Promise<void> {
  const orderResult = await query<{ customer_id: string; restaurant_id: string; status: string }>(
    'SELECT customer_id, restaurant_id, status FROM orders WHERE id = $1',
    [orderId]
  );
  const order = orderResult.rows[0];
  if (!order) return;
  if (!['ready_for_pickup', 'confirmed'].includes(order.status)) return;

  const cancelled = await updateOrderStatus(orderId, 'cancelled', {
    cancellation_reason: 'No rider available',
    cancelled_at: new Date(),
    payment_status: 'refunded',
  });

  if (!cancelled) return;

  const { initiateRefund } = await import('./refund.service');
  void initiateRefund(orderId);

  const { emitOrderStatusChanged, emitToRestaurant } = await import('./socket.service');
  emitOrderStatusChanged(cancelled, order.customer_id);
  void sendPushNotification(
    order.customer_id,
    'Order Cancelled',
    "We couldn't find a rider for your order. A refund has been initiated.",
    { type: 'order_cancelled', orderId }
  );

  const rResult = await query<{ owner_id: string }>(
    'SELECT owner_id FROM restaurants WHERE id = $1', [order.restaurant_id]
  );
  if (rResult.rows[0]) {
    emitToRestaurant(rResult.rows[0].owner_id, cancelled);
    void sendPushNotification(
      rResult.rows[0].owner_id,
      'Order Cancelled',
      'Order was cancelled — no rider was available.',
      { type: 'order_cancelled', orderId }
    );
  }
}
