import { query } from '../config/database';
import { haversineDistance } from '../utils/haversine';
import { emitDeliveryRequest, emitSearchingRider } from './socket.service';
import { sendPushNotification } from './fcm.service';
import { logger } from '../utils/logger';
import { env } from '../config/env';

// Retry intervals and radius expansion when no riders found
const RETRY_INTERVAL_MS = 2 * 60 * 1000;   // 2 minutes between retries
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
     VALUES ($1, $2, $3, $4) RETURNING *`,
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
  // Try to copy last known location; if none exists, insert with (0,0) as placeholder
  const inserted = await query(
    `INSERT INTO rider_locations (rider_id, latitude, longitude, availability)
     SELECT $1, latitude, longitude, $2 FROM rider_locations
     WHERE rider_id = $1 ORDER BY timestamp DESC LIMIT 1`,
    [riderId, availability]
  );
  if ((inserted.rowCount ?? 0) === 0) {
    // No prior location — insert placeholder so rider shows as available
    await query(
      `INSERT INTO rider_locations (rider_id, latitude, longitude, availability)
       VALUES ($1, 0, 0, $2)`,
      [riderId, availability]
    );
  }
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
  radiusKm: number
): Promise<NearbyRider[]> {
  // Get latest location per rider that is 'available' and within 5 minutes old
  const result = await query<{ rider_id: string; latitude: number; longitude: number }>(
    `SELECT DISTINCT ON (rider_id) rider_id, latitude, longitude
     FROM rider_locations
     WHERE availability = 'available'
       AND timestamp > NOW() - INTERVAL '30 minutes'
     ORDER BY rider_id, timestamp DESC`
  );

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
    riders = await findNearbyRiders(restaurant.latitude, restaurant.longitude, radius);
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

  sendToNextRider(orderId, restaurant, customerAddress, order.delivery_fee);
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
      riders = await findNearbyRiders(restaurant.latitude, restaurant.longitude, radius);
      if (riders.length > 0) break;
    }

    if (riders.length > 0) {
      // Rider found — start normal dispatch
      retrySessionsNoRider.delete(orderId);
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
      sendToNextRider(orderId, restaurant, customerAddress, deliveryFee);
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
    scheduleRetry(orderId, restaurant, customerAddress, deliveryFee);
  }, RETRY_INTERVAL_MS);
}

// Cancel any pending retry when a rider accepts or order is cancelled externally
export function cancelRetrySession(orderId: string) {
  const session = retrySessionsNoRider.get(orderId);
  if (session?.retryTimeout) clearTimeout(session.retryTimeout);
  retrySessionsNoRider.delete(orderId);
}

function sendToNextRider(
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
    // Exhausted all riders, restart from beginning if time allows
    session.riderIndex = 0;
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
      sendToNextRider(orderId, restaurant, customerAddress, deliveryFee);
    }
  }, env.RIDER_TIMEOUT_SECONDS * 1000);
}

export function riderAccepted(orderId: string) {
  const session = dispatchSessions.get(orderId);
  if (session?.currentTimeout) clearTimeout(session.currentTimeout);
  dispatchSessions.delete(orderId);
  cancelRetrySession(orderId); // also clear any no-rider retry session
}

export function riderDeclined(orderId: string) {
  const session = dispatchSessions.get(orderId);
  if (!session) return;
  if (session.currentTimeout) clearTimeout(session.currentTimeout);
  session.riderIndex++;
  sendToNextRider(orderId, session.restaurant, session.customerAddress, session.deliveryFee);
}
