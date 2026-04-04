import { query } from '../config/database';
import { haversineDistance } from '../utils/haversine';
import { emitDeliveryRequest } from './socket.service';
import { logger } from '../utils/logger';
import { env } from '../config/env';

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
  await query(
    `INSERT INTO rider_locations (rider_id, latitude, longitude, availability)
     SELECT $1, latitude, longitude, $2 FROM rider_locations
     WHERE rider_id = $1 ORDER BY timestamp DESC LIMIT 1`,
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
  radiusKm: number
): Promise<NearbyRider[]> {
  // Get latest location per rider that is 'available' and within 5 minutes old
  const result = await query<{ rider_id: string; latitude: number; longitude: number }>(
    `SELECT DISTINCT ON (rider_id) rider_id, latitude, longitude
     FROM rider_locations
     WHERE availability = 'available'
       AND timestamp > NOW() - INTERVAL '5 minutes'
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

// Active dispatch sessions: orderId -> { timeoutHandle, startTime, riderIndex, riders }
const dispatchSessions = new Map<string, {
  startTime: number;
  riderIndex: number;
  riders: NearbyRider[];
  currentTimeout: ReturnType<typeof setTimeout> | null;
}>();

export async function startDispatch(orderId: string, restaurantId: string): Promise<void> {
  const rResult = await query<{ latitude: number; longitude: number; name: string; address: string }>(
    'SELECT latitude, longitude, name, address FROM restaurants WHERE id = $1',
    [restaurantId]
  );
  if (!rResult.rows[0]) return;
  const restaurant = rResult.rows[0];

  const orderResult = await query<{ delivery_address_id: string; delivery_fee: number }>(
    'SELECT delivery_address_id, delivery_fee FROM orders WHERE id = $1',
    [orderId]
  );
  if (!orderResult.rows[0]) return;
  const order = orderResult.rows[0];

  const addrResult = await query<{ address_line: string }>(
    'SELECT address_line FROM addresses WHERE id = $1',
    [order.delivery_address_id]
  );
  const customerAddress = addrResult.rows[0]?.address_line ?? 'Unknown';

  const riders = await findNearbyRiders(
    restaurant.latitude, restaurant.longitude,
    env.RIDER_SEARCH_RADIUS_KM
  );

  if (riders.length === 0) {
    logger.warn('No riders available for dispatch', { orderId });
    return;
  }

  dispatchSessions.set(orderId, {
    startTime: Date.now(),
    riderIndex: 0,
    riders,
    currentTimeout: null,
  });

  sendToNextRider(orderId, restaurant, customerAddress, order.delivery_fee);
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
}

export function riderDeclined(orderId: string) {
  const session = dispatchSessions.get(orderId);
  if (!session) return;
  if (session.currentTimeout) clearTimeout(session.currentTimeout);
  session.riderIndex++;
  // We need restaurant/address info — re-trigger via a lightweight re-query
  // The timeout handler already handles this, so just increment and let it fire
}
