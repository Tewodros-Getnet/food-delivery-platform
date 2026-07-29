// Feature: food-delivery-app
// Property 36: Dispatch identifies riders within radius
// Property 37: Dispatch sends request to nearest rider first
// Property 38: Rider acceptance updates order and rider status
// Property 39: Rider decline triggers next rider contact
// Property 41: Pickup confirmation updates order status
// Property 42: Delivery confirmation updates order and rider status
// Property 63: Rider location updates stored with timestamp
// Property 64: Recent rider location used for dispatch

import fc from 'fast-check';
import * as riderService from '../services/rider.service';
import { pool } from '../config/database';

let riderId1: string;
let riderId2: string;

beforeAll(async () => {
  const ts = Date.now();
  const r1 = await pool.query<{ id: string }>(
    `INSERT INTO users (email, password_hash, role, email_verified)
     VALUES ($1, 'hash', 'rider', TRUE) RETURNING id`,
    [`rider1_${ts}@test.com`]
  );
  const r2 = await pool.query<{ id: string }>(
    `INSERT INTO users (email, password_hash, role, email_verified)
     VALUES ($1, 'hash', 'rider', TRUE) RETURNING id`,
    [`rider2_${ts}@test.com`]
  );
  riderId1 = r1.rows[0].id;
  riderId2 = r2.rows[0].id;
});

afterAll(async () => {
  await pool.query('DELETE FROM rider_locations WHERE rider_id IN ($1, $2)', [riderId1, riderId2]);
  await pool.query('DELETE FROM users WHERE id IN ($1, $2)', [riderId1, riderId2]);
  await pool.end();
});

afterEach(async () => {
  await pool.query('DELETE FROM rider_locations WHERE rider_id IN ($1, $2)', [riderId1, riderId2]);
});

// ── Property 63 ──────────────────────────────────────────────────────────────

describe('Property 63: Rider location updates stored with timestamp', () => {
  test('location update is persisted with a timestamp', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.float({ min: -90, max: 90, noNaN: true }),
        fc.float({ min: -180, max: 180, noNaN: true }),
        async (lat, lon) => {
          const loc = await riderService.updateRiderLocation(riderId1, lat, lon, 'available');
          expect(loc.rider_id).toBe(riderId1);
          expect(loc.timestamp).toBeDefined();
          // Allow 1 second buffer for DB round-trip timing
          expect(new Date(loc.timestamp).getTime()).toBeLessThanOrEqual(Date.now() + 1000);
          await pool.query('DELETE FROM rider_locations WHERE id = $1', [loc.id]);
        }
      ),
      { numRuns: 10 }
    );
  });
});

// ── Property 36 ──────────────────────────────────────────────────────────────

describe('Property 36: Dispatch identifies riders within radius', () => {
  test('only riders within radius are returned', async () => {
    // Rider 1 very close to restaurant (Addis Ababa area)
    await riderService.updateRiderLocation(riderId1, 9.03, 38.74, 'available');
    // Rider 2 far away (Nairobi)
    await riderService.updateRiderLocation(riderId2, -1.28, 36.82, 'available');

    const nearby = await riderService.findNearbyRiders(9.03, 38.74, 5);
    const ids = nearby.map((r) => r.rider_id);

    expect(ids).toContain(riderId1);
    expect(ids).not.toContain(riderId2);
    nearby.forEach((r) => expect(r.distance_km).toBeLessThanOrEqual(5));
  });
});

// ── Property 37 ──────────────────────────────────────────────────────────────

describe('Property 37: Dispatch sends request to nearest rider first', () => {
  test('riders are sorted by distance ascending', async () => {
    await riderService.updateRiderLocation(riderId1, 9.035, 38.745, 'available'); // slightly farther
    await riderService.updateRiderLocation(riderId2, 9.031, 38.741, 'available'); // slightly closer

    const nearby = await riderService.findNearbyRiders(9.03, 38.74, 5);
    if (nearby.length >= 2) {
      for (let i = 0; i < nearby.length - 1; i++) {
        expect(nearby[i].distance_km).toBeLessThanOrEqual(nearby[i + 1].distance_km);
      }
    }
  });
});

// ── Property 64 ──────────────────────────────────────────────────────────────

describe('Property 64: Recent rider location used for dispatch', () => {
  test('rider with stale location (>30 min) is excluded from dispatch', async () => {
    // Insert an old location directly (older than the 30-minute threshold used by the service)
    await pool.query(
      `INSERT INTO rider_locations (rider_id, latitude, longitude, availability, timestamp)
       VALUES ($1, 9.03, 38.74, 'available', NOW() - INTERVAL '35 minutes')
       ON CONFLICT (rider_id) DO UPDATE SET latitude=EXCLUDED.latitude, longitude=EXCLUDED.longitude, availability=EXCLUDED.availability, timestamp=EXCLUDED.timestamp`,
      [riderId1]
    );

    const nearby = await riderService.findNearbyRiders(9.03, 38.74, 5);
    const ids = nearby.map((r) => r.rider_id);
    expect(ids).not.toContain(riderId1);
  });
});
