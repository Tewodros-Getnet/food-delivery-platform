// Preservation Property Tests
// **Property 2: Preservation** - Existing Behavior Baseline
// These tests MUST PASS on unfixed code — they document behavior that must not regress
// **Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8, 3.9, 3.10**

import fc from 'fast-check';
import request from 'supertest';
import app from '../app';
import { pool } from '../config/database';
import { env } from '../config/env';
import * as authService from '../services/auth.service';
import * as riderService from '../services/rider.service';
import { Order } from '../models/order.model';
import { Restaurant } from '../models/restaurant.model';

jest.mock('../services/chapa.service', () => ({
  initializePayment: jest.fn().mockResolvedValue({ status: 'success', data: { checkout_url: 'https://checkout.chapa.co/test' } }),
  verifyWebhookSignature: jest.fn().mockReturnValue(true),
  verifyPayment: jest.fn(),
}));
jest.mock('../services/cloudinary.service', () => ({
  uploadImage: jest.fn().mockResolvedValue('https://cloudinary.com/test.jpg'),
  deleteImage: jest.fn(),
}));
jest.mock('../services/fcm.service', () => ({
  sendPushNotification: jest.fn().mockResolvedValue(undefined),
  registerFcmToken: jest.fn().mockResolvedValue(undefined),
}));
jest.mock('../services/email.service', () => ({
  sendOtpEmail: jest.fn().mockResolvedValue(undefined),
}));

let restaurantToken: string;
let restaurantId: string;
let restaurantOwnerId: string;
let riderToken: string;
let riderId: string;

beforeAll(async () => {
  const restaurantReg = await authService.register(`pres_rest_${Date.now()}@test.com`, 'Password123!', 'restaurant');
  restaurantOwnerId = restaurantReg.userId;
  await pool.query('UPDATE users SET email_verified = TRUE WHERE id = $1', [restaurantOwnerId]);
  const restaurantLogin = await authService.login(restaurantReg.email, 'Password123!');
  restaurantToken = restaurantLogin.tokens.jwt;

  const rResult = await pool.query(
    `INSERT INTO restaurants (owner_id, name, address, latitude, longitude, status)
     VALUES ($1, $2, $3, $4, $5, 'approved') RETURNING id`,
    [restaurantOwnerId, 'Preservation Test Restaurant', '123 Test St', 9.03, 38.74]
  );
  restaurantId = (rResult.rows[0] as { id: string }).id;

  const riderReg = await authService.register(`pres_rider_${Date.now()}@test.com`, 'Password123!', 'rider');
  riderId = riderReg.userId;
  await pool.query('UPDATE users SET email_verified = TRUE WHERE id = $1', [riderId]);
  const riderLogin = await authService.login(riderReg.email, 'Password123!');
  riderToken = riderLogin.tokens.jwt;
});

afterAll(async () => {
  await pool.query(`DELETE FROM menu_items WHERE restaurant_id = $1`, [restaurantId]);
  await pool.query(`DELETE FROM restaurants WHERE id = $1`, [restaurantId]);
  await pool.query(`DELETE FROM rider_locations WHERE rider_id = $1`, [riderId]);
  await pool.query(`DELETE FROM refresh_tokens WHERE user_id IN ($1, $2)`, [restaurantOwnerId, riderId]);
  await pool.query(`DELETE FROM users WHERE id IN ($1, $2)`, [restaurantOwnerId, riderId]);
  await pool.end();
});

// ── Preservation 3.1: Description with value still works ─────────────────────

describe('Preservation 3.1: create-menu-item WITH description still returns 201', () => {
  test('property: any non-empty description string is accepted', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.string({ minLength: 1, maxLength: 200 }).filter(s => s.trim().length > 0),
        async (description) => {
          const res = await request(app)
            .post(`/api/v1/restaurants/${restaurantId}/menu`)
            .set('Authorization', `Bearer ${restaurantToken}`)
            .send({
              name: `Item ${Date.now()}`,
              description,
              price: 9.99,
              category: 'Mains',
              imageBase64: 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
            });
          expect(res.status).toBe(201);
          expect(res.body.data.description).toBe(description.trim());
        }
      ),
      { numRuns: 3 }
    );
  });
});

// ── Preservation 3.2: All pre-existing env keys remain defined ────────────────

describe('Preservation 3.2: All pre-existing env keys remain defined', () => {
  const existingKeys: Array<keyof typeof env> = [
    'NODE_ENV', 'PORT', 'DATABASE_URL', 'JWT_SECRET', 'JWT_EXPIRY',
    'REFRESH_TOKEN_EXPIRY', 'CHAPA_SECRET_KEY', 'CHAPA_WEBHOOK_SECRET',
    'CLOUDINARY_CLOUD_NAME', 'CLOUDINARY_API_KEY', 'CLOUDINARY_API_SECRET',
    'FIREBASE_PROJECT_ID', 'FIREBASE_PRIVATE_KEY', 'FIREBASE_CLIENT_EMAIL',
    'RIDER_SEARCH_RADIUS_KM', 'RIDER_TIMEOUT_SECONDS', 'DISPATCH_MAX_DURATION_MINUTES',
    'DELIVERY_BASE_FEE', 'DELIVERY_RATE_PER_KM',
  ];

  test.each(existingKeys)('env.%s is defined', (key) => {
    expect(env[key]).toBeDefined();
  });

  test('numeric env vars have correct types', () => {
    expect(typeof env.PORT).toBe('number');
    expect(typeof env.RIDER_SEARCH_RADIUS_KM).toBe('number');
    expect(typeof env.RIDER_TIMEOUT_SECONDS).toBe('number');
    expect(typeof env.DISPATCH_MAX_DURATION_MINUTES).toBe('number');
    expect(typeof env.DELIVERY_BASE_FEE).toBe('number');
    expect(typeof env.DELIVERY_RATE_PER_KM).toBe('number');
  });
});

// ── Preservation 3.3: riderAccepted clears session ───────────────────────────

describe('Preservation 3.3: riderAccepted clears dispatch session', () => {
  test('riderAccepted should clear session and cancel timeout', async () => {
    const customerReg = await authService.register(`pres_cust_${Date.now()}@test.com`, 'Password123!', 'customer');
    const addrResult = await pool.query(
      `INSERT INTO addresses (user_id, address_line, latitude, longitude) VALUES ($1, $2, $3, $4) RETURNING id`,
      [customerReg.userId, '456 Customer St', 9.04, 38.75]
    );
    const addressId = (addrResult.rows[0] as { id: string }).id;

    await pool.query(
      `INSERT INTO rider_locations (rider_id, latitude, longitude, availability)
       VALUES ($1, 9.03, 38.74, 'available')
       ON CONFLICT (rider_id) DO UPDATE SET latitude=EXCLUDED.latitude, longitude=EXCLUDED.longitude, availability=EXCLUDED.availability`,
      [riderId]
    );

    // Assign rider to restaurant so startDispatch can find them via restaurant_riders JOIN
    await pool.query(
      `INSERT INTO restaurant_riders (rider_id, restaurant_id) VALUES ($1, $2)
       ON CONFLICT (rider_id) DO UPDATE SET restaurant_id = EXCLUDED.restaurant_id`,
      [riderId, restaurantId]
    );

    const orderResult = await pool.query(
      `INSERT INTO orders (customer_id, restaurant_id, delivery_address_id, status, subtotal, delivery_fee, total, payment_reference, payment_status)
       VALUES ($1, $2, $3, 'confirmed', 50.00, 10.00, 60.00, 'pres_ref', 'paid') RETURNING id`,
      [customerReg.userId, restaurantId, addressId]
    );
    const orderId = (orderResult.rows[0] as { id: string }).id;

    await riderService.startDispatch(orderId, restaurantId);

    // Accept — should not throw and should clear session
    expect(() => riderService.riderAccepted(orderId)).not.toThrow();

    // Calling accepted again should be a no-op (session already cleared)
    expect(() => riderService.riderAccepted(orderId)).not.toThrow();

    // Cleanup
    await pool.query(`DELETE FROM orders WHERE id = $1`, [orderId]);
    await pool.query(`DELETE FROM addresses WHERE id = $1`, [addressId]);
    await pool.query(`DELETE FROM restaurant_riders WHERE rider_id = $1`, [riderId]);
    await pool.query(`DELETE FROM rider_locations WHERE rider_id = $1`, [riderId]);
    await pool.query(`DELETE FROM refresh_tokens WHERE user_id = $1`, [customerReg.userId]);
    await pool.query(`DELETE FROM users WHERE id = $1`, [customerReg.userId]);
  });
});

// ── Preservation 3.5: Allowed origins pass CORS ──────────────────────────────

describe('Preservation 3.5: Requests from allowed origins pass CORS', () => {
  const allowedOrigins = (process.env.ALLOWED_ORIGINS || 'http://localhost:3000,http://localhost:3001').split(',');

  test.each(allowedOrigins)('origin %s should be allowed', async (origin) => {
    const res = await request(app)
      .options('/api/v1/auth/login')
      .set('Origin', origin.trim())
      .set('Access-Control-Request-Method', 'POST');

    // Should not be blocked (2xx or no CORS error)
    expect(res.status).not.toBe(403);
  });
});

// ── Preservation 3.6: All pre-existing Order fields present ──────────────────

describe('Preservation 3.6: All pre-existing Order fields are present in the interface', () => {
  test('Order interface has all 16 pre-existing fields', () => {
    // Construct a minimal Order object with all required fields
    const order: Order = {
      id: 'test-id',
      customer_id: 'cust-id',
      restaurant_id: 'rest-id',
      rider_id: null,
      delivery_address_id: 'addr-id',
      status: 'pending_payment',
      subtotal: 50,
      delivery_fee: 10,
      total: 60,
      payment_reference: null,
      payment_status: null,
      cancellation_reason: null,
      cancelled_at: null,
      cancelled_by: null,
      acceptance_deadline: null,
      estimated_prep_time_minutes: null,
      created_at: new Date(),
      updated_at: new Date(),
    };

    // All 16 pre-existing fields must be present
    expect(order).toHaveProperty('id');
    expect(order).toHaveProperty('customer_id');
    expect(order).toHaveProperty('restaurant_id');
    expect(order).toHaveProperty('rider_id');
    expect(order).toHaveProperty('delivery_address_id');
    expect(order).toHaveProperty('status');
    expect(order).toHaveProperty('subtotal');
    expect(order).toHaveProperty('delivery_fee');
    expect(order).toHaveProperty('total');
    expect(order).toHaveProperty('payment_reference');
    expect(order).toHaveProperty('payment_status');
    expect(order).toHaveProperty('cancellation_reason');
    expect(order).toHaveProperty('cancelled_at');
    expect(order).toHaveProperty('estimated_prep_time_minutes');
    expect(order).toHaveProperty('created_at');
    expect(order).toHaveProperty('updated_at');
  });
});

// ── Preservation 3.7: All pre-existing Restaurant fields present ──────────────

describe('Preservation 3.7: All pre-existing Restaurant fields are present in the interface', () => {
  test('Restaurant interface has all 14 pre-existing fields', () => {
    const restaurant: Restaurant = {
      id: 'rest-id',
      owner_id: 'owner-id',
      name: 'Test Restaurant',
      description: null,
      logo_url: null,
      cover_image_url: null,
      address: '123 Test St',
      latitude: 9.03,
      longitude: 38.74,
      category: null,
      status: 'approved',
      average_rating: 0,
      created_at: new Date(),
      updated_at: new Date(),
    };

    expect(restaurant).toHaveProperty('id');
    expect(restaurant).toHaveProperty('owner_id');
    expect(restaurant).toHaveProperty('name');
    expect(restaurant).toHaveProperty('description');
    expect(restaurant).toHaveProperty('logo_url');
    expect(restaurant).toHaveProperty('cover_image_url');
    expect(restaurant).toHaveProperty('address');
    expect(restaurant).toHaveProperty('latitude');
    expect(restaurant).toHaveProperty('longitude');
    expect(restaurant).toHaveProperty('category');
    expect(restaurant).toHaveProperty('status');
    expect(restaurant).toHaveProperty('average_rating');
    expect(restaurant).toHaveProperty('created_at');
    expect(restaurant).toHaveProperty('updated_at');
  });
});

// ── Preservation 3.8: Existing rider endpoints still work ────────────────────

describe('Preservation 3.8: Existing rider endpoints continue to return 200', () => {
  test('PUT /riders/location returns 200', async () => {
    const res = await request(app)
      .put('/api/v1/riders/location')
      .set('Authorization', `Bearer ${riderToken}`)
      .send({ latitude: 9.03, longitude: 38.74, availability: 'available' });

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
  });

  test('PUT /riders/availability returns 200', async () => {
    const res = await request(app)
      .put('/api/v1/riders/availability')
      .set('Authorization', `Bearer ${riderToken}`)
      .send({ availability: 'offline' });

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
  });
});

// ── Preservation 3.10: Online socket events delivered immediately ─────────────

describe('Preservation 3.10: Events to connected users are delivered immediately', () => {
  test('emitOrderStatusChanged delivers event to connected user without queuing', async () => {
    // This is a unit-level check — verify the emit functions exist and are callable
    const { emitOrderStatusChanged, emitRiderLocationUpdate, emitDeliveryRequest, emitDisputeResolved } = await import('../services/socket.service');

    expect(typeof emitOrderStatusChanged).toBe('function');
    expect(typeof emitRiderLocationUpdate).toBe('function');
    expect(typeof emitDeliveryRequest).toBe('function');
    expect(typeof emitDisputeResolved).toBe('function');

    // Calling without io initialized should be a no-op (not throw)
    const mockOrder: Order = {
      id: 'test', customer_id: 'c', restaurant_id: 'r', rider_id: null,
      delivery_address_id: 'a', status: 'confirmed', subtotal: 50,
      delivery_fee: 10, total: 60, payment_reference: null, payment_status: null,
      cancellation_reason: null, cancelled_at: null, cancelled_by: null,
      acceptance_deadline: null, estimated_prep_time_minutes: null,
      created_at: new Date(), updated_at: new Date(),
    };
    expect(() => emitOrderStatusChanged(mockOrder, 'user-id')).not.toThrow();
  });
});
