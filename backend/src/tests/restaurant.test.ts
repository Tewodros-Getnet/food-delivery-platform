// Feature: food-delivery-app
// Property 9: Restaurant registration starts in pending status
// Property 11: Restaurant approval makes it visible to customers
// Property 12: Restaurant rejection updates status
// Property 21: Customer listings show only approved restaurants
// Property 48: Suspended restaurant hidden and orders cancelled

import fc from 'fast-check';
import * as restaurantService from '../services/restaurant.service';
import * as authService from '../services/auth.service';
import { pool } from '../config/database';

let ownerUserId: string;

beforeAll(async () => {
  await pool.query('DELETE FROM restaurants');
  await pool.query('DELETE FROM users WHERE role = $1', ['restaurant']);
  const { user } = await authService.register(`owner_${Date.now()}@test.com`, 'Password123!', 'restaurant');
  ownerUserId = user.id;
});

afterAll(async () => {
  await pool.query('DELETE FROM restaurants');
  await pool.query('DELETE FROM users WHERE id = $1', [ownerUserId]);
  await pool.end();
});

afterEach(async () => {
  await pool.query('DELETE FROM restaurants WHERE owner_id = $1', [ownerUserId]);
});

function makeInput(overrides = {}) {
  return {
    ownerId: ownerUserId,
    name: `Restaurant ${Date.now()}`,
    address: '123 Main St',
    latitude: 9.03,
    longitude: 38.74,
    ...overrides,
  };
}

// ── Property 9 ───────────────────────────────────────────────────────────────

describe('Property 9: Restaurant registration starts in pending status', () => {
  test('newly created restaurant always has status pending', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.string({ minLength: 3, maxLength: 50 }),
        async (name) => {
          const r = await restaurantService.createRestaurant(makeInput({ name }));
          expect(r.status).toBe('pending');
          await pool.query('DELETE FROM restaurants WHERE id = $1', [r.id]);
        }
      ),
      { numRuns: 10 }
    );
  });
});

// ── Property 11 ──────────────────────────────────────────────────────────────

describe('Property 11: Restaurant approval makes it visible to customers', () => {
  test('approved restaurant appears in customer listing', async () => {
    const r = await restaurantService.createRestaurant(makeInput());
    await restaurantService.updateRestaurantStatus(r.id, 'approved');
    const { restaurants } = await restaurantService.getRestaurants({});
    const found = restaurants.find((x) => x.id === r.id);
    expect(found).toBeDefined();
    expect(found?.status).toBe('approved');
  });
});

// ── Property 12 ──────────────────────────────────────────────────────────────

describe('Property 12: Restaurant rejection updates status', () => {
  test('rejected restaurant has status rejected', async () => {
    const r = await restaurantService.createRestaurant(makeInput());
    const updated = await restaurantService.updateRestaurantStatus(r.id, 'rejected');
    expect(updated?.status).toBe('rejected');
  });
});

// ── Property 21 ──────────────────────────────────────────────────────────────

describe('Property 21: Customer listings show only approved restaurants', () => {
  test('listing never returns pending, rejected, or suspended restaurants', async () => {
    const r1 = await restaurantService.createRestaurant(makeInput({ name: 'Pending One' }));
    const r2 = await restaurantService.createRestaurant(makeInput({ name: 'Approved One' }));
    await restaurantService.updateRestaurantStatus(r2.id, 'approved');

    const { restaurants } = await restaurantService.getRestaurants({});
    const ids = restaurants.map((r) => r.id);

    expect(ids).not.toContain(r1.id);
    expect(ids).toContain(r2.id);
    restaurants.forEach((r) => expect(r.status).toBe('approved'));
  });
});

// ── Property 48 ──────────────────────────────────────────────────────────────

describe('Property 48: Suspended restaurant hidden and orders cancelled', () => {
  test('suspended restaurant does not appear in customer listing', async () => {
    const r = await restaurantService.createRestaurant(makeInput());
    await restaurantService.updateRestaurantStatus(r.id, 'approved');
    await restaurantService.suspendRestaurant(r.id);

    const { restaurants } = await restaurantService.getRestaurants({});
    const ids = restaurants.map((x) => x.id);
    expect(ids).not.toContain(r.id);
  });
});
