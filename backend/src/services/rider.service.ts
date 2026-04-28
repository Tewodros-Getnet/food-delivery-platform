import { query } from '../config/database';
import { haversineDistance } from '../utils/haversine';
import { emitDeliveryRequest, emitSearchingRider } from './socket.service';
import { sendPushNotification } from './fcm.service';
import { logger } from '../utils/logger';
import { env } from '../config/env';

// Retry intervals and radius expansion when no riders found
const RETRY_INTERVAL_MS = 1 * 60 * 1000;   // 1 minute between retries
const MAX_RETRIES = 10;                      // 10 × 2min = 20 minutes max
const RADIUS_STEPS_KM = [5, 8, 12];         // expand radius on each immediate attempt

// Active no-rider retry sessions: orderId → retry state
const retrySessionsNoRider = new Map<string, {
  retryCount: number;
  retryTimeout: ReturnType<typeof setTimeout> | null;
  restaurantId: string;
  customerId: string;
  restaurantOwnerId: string;
}>();

export interface RiderLocation {
  id: string;
  rider_id: string;
  latitude: number;
  longitude: number;
  availability: 'available' | 'on_delivery' | 'offline';
  timestamp: Date;
}

export async function updateRiderLocation(
  riderId: string,
  latitude: number,
  longitude: number,
  availability: 'available' | 'on_delivery' | 'offline'
): Promise<RiderLocation> {
  const result = await query<RiderLocation>(
    `INSERT INTO rider_locations (rider_id, latitude, longitude, availability)
     VALUES ($1, $2, $3, $4)
     ON CONFLICT (rider_id) DO UPDATE
       SET latitude = EXCLUDED.latitude,
           longitude = EXCLUDED.longitude,
           availability = EXCLUDED.availability,
           timestamp = NOW()
     RETURNING *`,
    [riderId, latitude, longitude, availability]
  );
  return result.rows[0];
}

export async function getLatestRiderLocation(riderId: string): Promise<RiderLocation | null> {
  const result = await query<RiderLocation>(
    `SELECT * FROM rider_locations WHERE rider_id = $1 ORDER BY timestamp DESC LIMIT 1`,
    [riderId]
  );
  return result.rows[0] ?? null;
}

export async function setRiderAvailability(
  riderId: string,
  availability: 'available' | 'on_delivery' | 'offline'
): Promise<void> {
  await query(
    `INSERT INTO rider_locations (rider_id, latitude, longitude, availability)
     VALUES ($1, 0, 0, $2)
     ON CONFLICT (rider_id) DO UPDATE
       SET availability = EXCLUDED.availability,
           timestamp = NOW()`,
    [riderId, availability]
  );
}

interface NearbyRider {
  rider_id: string;
  latitude: number;
  longitude: number;
  distance_km: number;
}

export async function findNearbyRiders(
  restaurantLat: number,
  restaurantLon: number,
  radiusKm: number,
  restaurantId?: string
): Promise<NearbyRider[]> {
  // Only dispatch riders assigned to this restaurant (if restaurantId provided)
  let sql: string;
  let params: unknown[];

  if (restaurantId) {
    sql = `SELECT rl.rider_id, rl.latitude, rl.longitude
           FROM rider_locations rl
           JOIN restaurant_riders rr ON rr.rider_id = rl.rider_id AND rr.restaurant_id = $1
           WHERE rl.availability = 'available'
             AND rl.timestamp > NOW() - INTERVAL '30 minutes'`;
    params = [restaurantId];
  } else {
    sql = `SELECT rider_id, latitude, longitude
           FROM rider_locations
           WHERE availability = 'available'
             AND timestamp > NOW() - INTERVAL '30 minutes'`;
    params = [];
  }

  const result = await query<{ rider_id: string; latitude: number; longitude: number }>(sql, params);

  return result.rows
    .map((r) => ({
      rider_id: r.rider_id,
      latitude: r.latitude,
      longitude: r.longitude,
      distance_km: haversineDistance(restaurantLat, restaurantLon, r.latitude, r.longitude),
    }))
    .filter((r) => r.distance_km <= radiusKm)
    .sort((a, b) => a.distance_km - b.distance_km);
}

// Active dispatch sessions: orderId -> session state
const dispatchSessions = new Map<string, {
  startTime: number;
  riderIndex: number;
  riders: NearbyRider[];
  currentTimeout: ReturnType<typeof setTimeout> | null;
  restaurant: { name: string; address: string };
  customerAddress: string;
  deliveryFee: number;
}>();

export async function startDispatch(orderId: string, restaurantId: string): Promise<void> {
  const rResult = await query<{ latitude: number; longitude: number; name: string; address: string }>(
    'SELECT latitude, longitude, name, address FROM restaurants WHERE id = $1',
    [restaurantId]
  );
  if (!rResult.rows[0]) return;
  const restaurant = rResult.rows[0];

  const orderResult = await query<{ delivery_address_id: string; delivery_fee: number; customer_id: string }>(
    'SELECT delivery_address_id, delivery_fee, customer_id FROM orders WHERE id = $1',
    [orderId]
  );
  if (!orderResult.rows[0]) return;
  const order = orderResult.rows[0];

  const addrResult = await query<{ address_line: string }>(
    'SELECT address_line FROM addresses WHERE id = $1',
    [order.delivery_address_id]
  );
  const customerAddress = addrResult.rows[0]?.address_line ?? 'Unknown';

  // Try expanding radius immediately before giving up
  let riders: NearbyRider[] = [];
  let usedRadius = env.RIDER_SEARCH_RADIUS_KM;
  for (const radius of RADIUS_STEPS_KM) {
    riders = await findNearbyRiders(restaurant.latitude, restaurant.longitude, radius, restaurantId);
    usedRadius = radius;
    logger.info('Dispatch: searching riders', {
      orderId, restaurantLat: restaurant.latitude, restaurantLon: restaurant.longitude,
      radiusKm: radius, ridersFound: riders.length,
    });
    if (riders.length > 0) break;
  }

  if (riders.length === 0) {
    // No riders found even after expanding radius — fetch restaurant owner for notifications
    const ownerResult = await query<{ owner_id: string }>(
      'SELECT owner_id FROM restaurants WHERE id = $1', [restaurantId]
    );
    const restaurantOwnerId = ownerResult.rows[0]?.owner_id ?? '';

    logger.warn('No riders available — starting retry schedule', { orderId });

    // Notify customer and restaurant immediately
    emitSearchingRider({
      customerId: order.customer_id,
      restaurantOwnerId,
      orderId,
      retryCount: 0,
      maxRetries: MAX_RETRIES,
    });

    // Store retry session
    retrySessionsNoRider.set(orderId, {
      retryCount: 0,
      retryTimeout: null,
      restaurantId,
      customerId: order.customer_id,
      restaurantOwnerId,
    });
    await persistUpsertRetrySession(orderId, { retryCount: 0, restaurantId, customerId: order.customer_id, restaurantOwnerId });

    scheduleRetry(orderId, restaurant, customerAddress, order.delivery_fee);
    return;
  }

  logger.info('Dispatch started', {
    orderId, riderCount: riders.length, radiusKm: usedRadius,
    riders: riders.map(r => ({ id: r.rider_id, distanceKm: r.distance_km })),
  });

  dispatchSessions.set(orderId, {
    startTime: Date.now(),
    riderIndex: 0,
    riders,
    currentTimeout: null,
    restaurant: { name: restaurant.name, address: restaurant.address },
    customerAddress,
    deliveryFee: order.delivery_fee,
  });
  await persistUpsertDispatchSession(orderId, { riderIndex: 0, riders, restaurant: { name: restaurant.name, address: restaurant.address }, customerAddress, deliveryFee: order.delivery_fee, startTime: Date.now() });

  void sendToNextRider(orderId, restaurant, customerAddress, order.delivery_fee);
}

function scheduleRetry(
  orderId: string,
  restaurant: { latitude: number; longitude: number; name: string; address: string },
  customerAddress: string,
  deliveryFee: number
) {
  const session = retrySessionsNoRider.get(orderId);
  if (!session) return;

  session.retryTimeout = setTimeout(async () => {
    // Check order is still waiting for a rider
    const orderCheck = await query<{ status: string }>(
      'SELECT status FROM orders WHERE id = $1', [orderId]
    );
    if (!orderCheck.rows[0] || orderCheck.rows[0].status !== 'ready_for_pickup') {
      retrySessionsNoRider.delete(orderId);
      return;
    }

    session.retryCount++;
    logger.info('Retrying dispatch', { orderId, retryCount: session.retryCount });

    // Try all radius steps again
    let riders: NearbyRider[] = [];
    for (const radius of RADIUS_STEPS_KM) {
      riders = await findNearbyRiders(restaurant.latitude, restaurant.longitude, radius, session.restaurantId);
      if (riders.length > 0) break;
    }

    if (riders.length > 0) {
      // Rider found — start normal dispatch
      retrySessionsNoRider.delete(orderId);
      await persistDeleteRetrySession(orderId);
      logger.info('Rider found on retry', { orderId, retryCount: session.retryCount });
      dispatchSessions.set(orderId, {
        startTime: Date.now(),
        riderIndex: 0,
        riders,
        currentTimeout: null,
        restaurant: { name: restaurant.name, address: restaurant.address },
        customerAddress,
        deliveryFee,
      });
      await persistUpsertDispatchSession(orderId, { riderIndex: 0, riders, restaurant: { name: restaurant.name, address: restaurant.address }, customerAddress, deliveryFee, startTime: Date.now() });
      void sendToNextRider(orderId, restaurant, customerAddress, deliveryFee);
      return;
    }

    if (session.retryCount >= MAX_RETRIES) {
      // Exhausted all retries — cancel order and refund
      retrySessionsNoRider.delete(orderId);
      logger.warn('Max retries reached — cancelling order', { orderId });
      const { cancelOrderNoRider } = await import('./order.service');
      void cancelOrderNoRider(orderId);
      return;
    }

    // Still no rider — notify again and schedule next retry
    emitSearchingRider({
      customerId: session.customerId,
      restaurantOwnerId: session.restaurantOwnerId,
      orderId,
      retryCount: session.retryCount,
      maxRetries: MAX_RETRIES,
    });
    await persistUpsertRetrySession(orderId, { retryCount: session.retryCount, restaurantId: session.restaurantId, customerId: session.customerId, restaurantOwnerId: session.restaurantOwnerId });
    scheduleRetry(orderId, restaurant, customerAddress, deliveryFee);
  }, RETRY_INTERVAL_MS);
}

// Cancel any pending retry when a rider accepts or order is cancelled externally
export function cancelRetrySession(orderId: string) {
  const session = retrySessionsNoRider.get(orderId);
  if (session?.retryTimeout) clearTimeout(session.retryTimeout);
  retrySessionsNoRider.delete(orderId);
  void persistDeleteRetrySession(orderId);
}

async function sendToNextRider(
  orderId: string,
  restaurant: { name: string; address: string },
  customerAddress: string,
  deliveryFee: number
) {
  const session = dispatchSessions.get(orderId);
  if (!session) return;

  const elapsed = (Date.now() - session.startTime) / 1000 / 60;
  if (elapsed >= env.DISPATCH_MAX_DURATION_MINUTES) {
    logger.warn('Dispatch timed out — no rider accepted', { orderId });
    dispatchSessions.delete(orderId);
    return;
  }

  if (session.riderIndex >= session.riders.length) {
    // All riders exhausted — transition to no-rider retry schedule
    dispatchSessions.delete(orderId);
    void persistDeleteDispatchSession(orderId);

    // Fetch restaurant owner for notifications
    const ownerResult = await query<{ owner_id: string; id: string }>(
      `SELECT r.owner_id, r.id FROM restaurants r
       JOIN orders o ON o.restaurant_id = r.id
       WHERE o.id = $1`,
      [orderId]
    );
    const restaurantOwnerId = ownerResult.rows[0]?.owner_id ?? '';
    const restaurantId = ownerResult.rows[0]?.id ?? '';

    const orderResult = await query<{ customer_id: string }>(
      'SELECT customer_id FROM orders WHERE id = $1', [orderId]
    );
    const customerId = orderResult.rows[0]?.customer_id ?? '';

    logger.warn('All riders exhausted — transitioning to retry schedule', { orderId });

    emitSearchingRider({
      customerId,
      restaurantOwnerId,
      orderId,
      retryCount: 0,
      maxRetries: MAX_RETRIES,
    });

    retrySessionsNoRider.set(orderId, {
      retryCount: 0,
      retryTimeout: null,
      restaurantId,
      customerId,
      restaurantOwnerId,
    });
    void persistUpsertRetrySession(orderId, { retryCount: 0, restaurantId, customerId, restaurantOwnerId });

    // Need restaurant lat/lon for scheduleRetry — fetch it
    const rResult = await query<{ latitude: number; longitude: number; name: string; address: string }>(
      'SELECT latitude, longitude, name, address FROM restaurants WHERE id = $1',
      [restaurantId]
    );
    if (rResult.rows[0]) {
      scheduleRetry(orderId, rResult.rows[0], customerAddress, deliveryFee);
    }
    return;
  }

  const rider = session.riders[session.riderIndex];
  const expiresAt = new Date(Date.now() + env.RIDER_TIMEOUT_SECONDS * 1000).toISOString();

  emitDeliveryRequest(rider.rider_id, {
    orderId,
    restaurantName: restaurant.name,
    restaurantAddress: restaurant.address,
    customerAddress,
    deliveryFee,
    estimatedDistance: rider.distance_km,
    expiresAt,
  });

  // Also send FCM push so rider is notified even when app is backgrounded/closed
  void sendPushNotification(
    rider.rider_id,
    'New Delivery Request',
    `From ${restaurant.name} — ETB ${deliveryFee} (${rider.distance_km.toFixed(1)} km)`,
    { type: 'delivery_request', orderId, expiresAt }
  );

  logger.info('Delivery request sent to rider', { orderId, riderId: rider.rider_id });

  session.currentTimeout = setTimeout(() => {
    const s = dispatchSessions.get(orderId);
    if (s) {
      s.riderIndex++;
      void persistUpsertDispatchSession(orderId, { riderIndex: s.riderIndex, riders: s.riders, restaurant: s.restaurant, customerAddress: s.customerAddress, deliveryFee: s.deliveryFee, startTime: s.startTime });
      void sendToNextRider(orderId, restaurant, customerAddress, deliveryFee);
    }
  }, env.RIDER_TIMEOUT_SECONDS * 1000);
}

export function riderAccepted(orderId: string) {
  const session = dispatchSessions.get(orderId);
  if (session?.currentTimeout) clearTimeout(session.currentTimeout);
  dispatchSessions.delete(orderId);
  void persistDeleteDispatchSession(orderId);
  cancelRetrySession(orderId); // also clear any no-rider retry session
}

export function riderDeclined(orderId: string) {
  const session = dispatchSessions.get(orderId);
  if (!session) return;
  if (session.currentTimeout) clearTimeout(session.currentTimeout);
  session.riderIndex++;
  void sendToNextRider(orderId, session.restaurant, session.customerAddress, session.deliveryFee);
}

// ── DB persistence helpers ────────────────────────────────────────────────────

async function persistUpsertDispatchSession(orderId: string, session: {
  riderIndex: number;
  riders: NearbyRider[];
  restaurant: { name: string; address: string };
  customerAddress: string;
  deliveryFee: number;
  startTime: number;
}): Promise<void> {
  await query(
    `INSERT INTO dispatch_sessions (order_id, rider_index, riders, restaurant, customer_address, delivery_fee, start_time)
     VALUES ($1, $2, $3, $4, $5, $6, $7)
     ON CONFLICT (order_id) DO UPDATE
       SET rider_index = EXCLUDED.rider_index,
           riders = EXCLUDED.riders,
           restaurant = EXCLUDED.restaurant,
           customer_address = EXCLUDED.customer_address,
           delivery_fee = EXCLUDED.delivery_fee,
           start_time = EXCLUDED.start_time`,
    [orderId, session.riderIndex, JSON.stringify(session.riders), JSON.stringify(session.restaurant),
     session.customerAddress, session.deliveryFee, session.startTime]
  );
}

async function persistDeleteDispatchSession(orderId: string): Promise<void> {
  await query('DELETE FROM dispatch_sessions WHERE order_id = $1', [orderId]);
}

async function persistUpsertRetrySession(orderId: string, session: {
  retryCount: number;
  restaurantId: string;
  customerId: string;
  restaurantOwnerId: string;
}): Promise<void> {
  await query(
    `INSERT INTO retry_sessions_no_rider (order_id, retry_count, restaurant_id, customer_id, restaurant_owner_id)
     VALUES ($1, $2, $3, $4, $5)
     ON CONFLICT (order_id) DO UPDATE
       SET retry_count = EXCLUDED.retry_count`,
    [orderId, session.retryCount, session.restaurantId, session.customerId, session.restaurantOwnerId]
  );
}

async function persistDeleteRetrySession(orderId: string): Promise<void> {
  await query('DELETE FROM retry_sessions_no_rider WHERE order_id = $1', [orderId]);
}

export async function recoverDispatchSessions(): Promise<void> {
  logger.info('Recovering dispatch sessions from DB...');

  // Recover dispatch sessions
  const dsResult = await query<{
    order_id: string; rider_index: number; riders: NearbyRider[];
    restaurant: { name: string; address: string; latitude: number; longitude: number };
    customer_address: string; delivery_fee: number; start_time: number;
  }>(
    `SELECT ds.*, o.status FROM dispatch_sessions ds
     JOIN orders o ON o.id = ds.order_id
     WHERE o.status = 'ready_for_pickup'`
  );

  for (const row of dsResult.rows) {
    const elapsed = (Date.now() - row.start_time) / 1000 / 60;
    if (elapsed >= env.DISPATCH_MAX_DURATION_MINUTES) {
      logger.warn('Stale dispatch session on startup — cancelling order', { orderId: row.order_id });
      await persistDeleteDispatchSession(row.order_id);
      const { cancelOrderNoRider } = await import('./order.service');
      void cancelOrderNoRider(row.order_id);
      continue;
    }
    dispatchSessions.set(row.order_id, {
      startTime: row.start_time,
      riderIndex: row.rider_index,
      riders: row.riders,
      currentTimeout: null,
      restaurant: row.restaurant,
      customerAddress: row.customer_address,
      deliveryFee: row.delivery_fee,
    });
    logger.info('Resumed dispatch session', { orderId: row.order_id });
    void sendToNextRider(row.order_id, row.restaurant, row.customer_address, row.delivery_fee);
  }

  // Recover retry sessions
  const rsResult = await query<{
    order_id: string; retry_count: number; restaurant_id: string;
    customer_id: string; restaurant_owner_id: string;
  }>(
    `SELECT rs.* FROM retry_sessions_no_rider rs
     JOIN orders o ON o.id = rs.order_id
     WHERE o.status = 'ready_for_pickup'`
  );

  for (const row of rsResult.rows) {
    const rResult = await query<{ latitude: number; longitude: number; name: string; address: string }>(
      'SELECT latitude, longitude, name, address FROM restaurants WHERE id = $1',
      [row.restaurant_id]
    );
    if (!rResult.rows[0]) continue;
    const restaurant = rResult.rows[0];

    const addrResult = await query<{ address_line: string }>(
      `SELECT a.address_line FROM addresses a
       JOIN orders o ON o.delivery_address_id = a.id
       WHERE o.id = $1`,
      [row.order_id]
    );
    const customerAddress = addrResult.rows[0]?.address_line ?? 'Unknown';

    const orderResult = await query<{ delivery_fee: number }>(
      'SELECT delivery_fee FROM orders WHERE id = $1', [row.order_id]
    );
    const deliveryFee = orderResult.rows[0]?.delivery_fee ?? 0;

    retrySessionsNoRider.set(row.order_id, {
      retryCount: row.retry_count,
      retryTimeout: null,
      restaurantId: row.restaurant_id,
      customerId: row.customer_id,
      restaurantOwnerId: row.restaurant_owner_id,
    });
    logger.info('Resumed retry session', { orderId: row.order_id, retryCount: row.retry_count });
    scheduleRetry(row.order_id, restaurant, customerAddress, deliveryFee);
  }

  logger.info('Dispatch session recovery complete', {
    dispatchSessions: dsResult.rowCount,
    retrySessions: rsResult.rowCount,
  });
}
