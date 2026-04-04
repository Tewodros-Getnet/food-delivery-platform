// Feature: food-delivery-app
// Property 68: API responses follow consistent envelope
// Property 69: Invalid request bodies return 422
// Property 72: Non-existent resources return 404
// Property 73: Unauthorized resource access returns 403

import request from 'supertest';
import fc from 'fast-check';
import app from '../app';
import * as authService from '../services/auth.service';
import { pool } from '../config/database';

let customerToken: string;
let restaurantToken: string;

beforeAll(async () => {
  const c = await authService.register(`api_cust_${Date.now()}@test.com`, 'Password123!', 'customer');
  const r = await authService.register(`api_rest_${Date.now()}@test.com`, 'Password123!', 'restaurant');
  customerToken = c.tokens.jwt;
  restaurantToken = r.tokens.jwt;
});

afterAll(async () => {
  await pool.query(`DELETE FROM users WHERE email LIKE 'api_%@test.com'`);
  await pool.end();
});

// ── Property 68 ──────────────────────────────────────────────────────────────

describe('Property 68: API responses follow consistent envelope', () => {
  test('health endpoint returns success envelope', async () => {
    const res = await request(app).get('/health');
    expect(res.body).toHaveProperty('success', true);
    expect(res.body).toHaveProperty('data');
    expect(res.body).toHaveProperty('error', null);
  });

  test('all API responses have success, data, error fields', async () => {
    const res = await request(app)
      .get('/api/v1/restaurants')
      .expect(200);
    expect(res.body).toHaveProperty('success');
    expect(res.body).toHaveProperty('data');
    expect(res.body).toHaveProperty('error');
  });
});

// ── Property 69 ──────────────────────────────────────────────────────────────

describe('Property 69: Invalid request bodies return 422', () => {
  test('registration with invalid email returns 422', async () => {
    const res = await request(app)
      .post('/api/v1/auth/register')
      .send({ email: 'not-an-email', password: 'pass123', role: 'customer' });
    expect(res.status).toBe(422);
    expect(res.body.success).toBe(false);
    expect(res.body).toHaveProperty('details');
  });

  test('registration with invalid role returns 422', async () => {
    const res = await request(app)
      .post('/api/v1/auth/register')
      .send({ email: 'valid@test.com', password: 'Password123!', role: 'superadmin' });
    expect(res.status).toBe(422);
  });

  test('property: any missing required field returns 422', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.constantFrom(
          { email: 'test@test.com', password: 'pass123' }, // missing role
          { email: 'test@test.com', role: 'customer' },    // missing password
          { password: 'pass123', role: 'customer' },       // missing email
        ),
        async (body) => {
          const res = await request(app).post('/api/v1/auth/register').send(body);
          expect([422, 400]).toContain(res.status);
        }
      ),
      { numRuns: 3 }
    );
  });
});

// ── Property 72 ──────────────────────────────────────────────────────────────

describe('Property 72: Non-existent resources return 404', () => {
  test('getting non-existent restaurant returns 404', async () => {
    const res = await request(app)
      .get('/api/v1/restaurants/00000000-0000-0000-0000-000000000000');
    expect(res.status).toBe(404);
    expect(res.body.success).toBe(false);
  });

  test('getting non-existent order returns 404', async () => {
    const res = await request(app)
      .get('/api/v1/orders/00000000-0000-0000-0000-000000000000')
      .set('Authorization', `Bearer ${customerToken}`);
    expect(res.status).toBe(404);
  });
});

// ── Property 73 ──────────────────────────────────────────────────────────────

describe('Property 73: Unauthorized resource access returns 403', () => {
  test('customer cannot access admin endpoints', async () => {
    const res = await request(app)
      .get('/api/v1/admin/users')
      .set('Authorization', `Bearer ${customerToken}`);
    expect(res.status).toBe(403);
  });

  test('restaurant cannot create orders', async () => {
    const res = await request(app)
      .post('/api/v1/orders')
      .set('Authorization', `Bearer ${restaurantToken}`)
      .send({ restaurantId: 'test', deliveryAddressId: 'test', items: [] });
    expect(res.status).toBe(403);
  });

  test('unauthenticated request to protected endpoint returns 401', async () => {
    const res = await request(app).get('/api/v1/orders');
    expect(res.status).toBe(401);
  });
});
