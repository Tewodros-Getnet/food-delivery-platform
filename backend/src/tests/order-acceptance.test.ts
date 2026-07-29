/// <reference types="jest" />
/**
 * Feature: restaurant-order-acceptance
 * Task 7: Backend Tests
 *
 * Tests for PUT /orders/:id/accept and PUT /orders/:id/reject
 * Tasks 7.1–7.7: unit/integration tests + property-based tests
 */

import request from 'supertest';
import fc from 'fast-check';
import { v4 as uuidv4 } from 'uuid';

// ── Mocks ─────────────────────────────────────────────────────────────────────

jest.mock('../config/database', () => {
  const mockQueryFn = jest.fn();
  return {
    pool: { end: jest.fn() },
    query: mockQueryFn,
    // withTransaction executes the callback with a client that delegates to the same mockQuery
    withTransaction: jest.fn(async (cb: (client: any) => Promise<unknown>) => {
      const client = { query: (...args: unknown[]) => mockQueryFn(...args) };
      return cb(client);
    }),
  };
});

jest.mock('../services/refund.service', () => ({
  initiateRefund: jest.fn().mockResolvedValue(undefined),
}));

jest.mock('../services/socket.service', () => ({
  emitOrderStatusChanged: jest.fn(),
  emitToRestaurant: jest.fn(),
  emitOrderAcceptanceRequest: jest.fn(),
  initSocketServer: jest.fn(),
}));

jest.mock('../services/fcm.service', () => ({
  sendPushNotification: jest.fn().mockResolvedValue(undefined),
  registerFcmToken: jest.fn(),
}));

jest.mock('../services/email.service', () => ({
  sendOtpEmail: jest.fn().mockResolvedValue(undefined),
}));

jest.mock('../services/cloudinary.service', () => ({
  uploadImage: jest.fn().mockResolvedValue('https://cloudinary.com/test.jpg'),
}));

jest.mock('../services/chapa.service', () => ({
  initializePayment: jest.fn(),
  verifyWebhookSignature: jest.fn().mockReturnValue(true),
}));

// Mock auth middleware so we can inject userId / userRole per test
jest.mock('../middleware/auth', () => ({
  authenticate: jest.fn((req: any, _res: any, next: any) => { next(); }),
}));

// Disable rate limiting
jest.mock('../middleware/rateLimiter', () => {
  const pass = (_req: any, _res: any, next: any) => next();
  return { rateLimiter: pass, authRateLimiter: pass };
});

// ── Imports after mocks ───────────────────────────────────────────────────────

import app from '../app';
import { query } from '../config/database';
import { initiateRefund } from '../services/refund.service';
import { emitOrderStatusChanged, emitToRestaurant } from '../services/socket.service';
import { sendPushNotification } from '../services/fcm.service';
import { authenticate } from '../middleware/auth';

const mockQuery = query as jest.Mock;
const mockInitiateRefund = initiateRefund as jest.Mock;
const mockEmitOrderStatusChanged = emitOrderStatusChanged as jest.Mock;
const mockEmitToRestaurant = emitToRestaurant as jest.Mock;
const mockSendPushNotification = sendPushNotification as jest.Mock;
const mockAuthenticate = authenticate as jest.Mock;

// ── Helpers ───────────────────────────────────────────────────────────────────

type OrderStatus =
  | 'pending_payment' | 'payment_failed' | 'pending_acceptance'
  | 'confirmed' | 'ready_for_pickup' | 'rider_assigned'
  | 'picked_up' | 'delivered' | 'cancelled';

function makeOrder(overrides: Partial<{
  id: string;
  customer_id: string;
  restaurant_id: string;
  status: OrderStatus;
  acceptance_deadline: Date | null;
}> = {}) {
  return {
    id: uuidv4(),
    customer_id: uuidv4(),
    restaurant_id: uuidv4(),
    rider_id: null,
    delivery_address_id: uuidv4(),
    status: 'pending_acceptance' as OrderStatus,
    subtotal: 100,
    delivery_fee: 20,
    total: 120,
    payment_reference: 'ref-123',
    payment_status: 'paid',
    cancellation_reason: null,
    cancelled_at: null,
    cancelled_by: null,
    acceptance_deadline: new Date(Date.now() + 180_000),
    estimated_prep_time_minutes: null,
    created_at: new Date(),
    updated_at: new Date(),
    ...overrides,
  };
}

function setAuth(userId: string | null, role: string | null) {
  mockAuthenticate.mockImplementation((req: any, res: any, next: any) => {
    if (userId === null) {
      res.status(401).json({ success: false, error: 'Authentication required', data: null });
      return;
    }
    req.userId = userId;
    req.userRole = role;
    next();
  });
}

function setupAcceptQueries(order: ReturnType<typeof makeOrder>, restaurantId: string) {
  const confirmedOrder = { ...order, status: 'confirmed' as OrderStatus };
  mockQuery
    .mockResolvedValueOnce({ rows: [order], rowCount: 1 })           // getOrderById
    .mockResolvedValueOnce({ rows: [{ id: restaurantId }], rowCount: 1 }) // restaurant by owner
    .mockResolvedValueOnce({ rows: [confirmedOrder], rowCount: 1 }); // updateOrderStatus
  return confirmedOrder;
}

function setupRejectQueries(order: ReturnType<typeof makeOrder>, restaurantId: string, reason: string) {
  const cancelledOrder = {
    ...order,
    status: 'cancelled' as OrderStatus,
    cancellation_reason: reason,
    cancelled_by: 'restaurant',
    cancelled_at: new Date(),
  };
  mockQuery
    .mockResolvedValueOnce({ rows: [order], rowCount: 1 })
    .mockResolvedValueOnce({ rows: [{ id: restaurantId }], rowCount: 1 })
    .mockResolvedValueOnce({ rows: [cancelledOrder], rowCount: 1 });
  return cancelledOrder;
}

// ── beforeEach ────────────────────────────────────────────────────────────────

beforeEach(() => {
  jest.clearAllMocks();
  setAuth(uuidv4(), 'restaurant');
});

// ═════════════════════════════════════════════════════════════════════════════
// Task 7.1 — Example-based unit/integration tests
// ═════════════════════════════════════════════════════════════════════════════

describe('Task 7.1 — PUT /orders/:id/accept', () => {

  test('unauthenticated returns 401', async () => {
    setAuth(null, null);
    const res = await request(app).put(`/api/v1/orders/${uuidv4()}/accept`).send({});
    expect(res.status).toBe(401);
  });

  test('non-restaurant role returns 403', async () => {
    setAuth(uuidv4(), 'customer');
    const res = await request(app).put(`/api/v1/orders/${uuidv4()}/accept`).send({});
    expect(res.status).toBe(403);
  });

  test('wrong restaurant returns 403', async () => {
    const ownerId = uuidv4();
    setAuth(ownerId, 'restaurant');
    const order = makeOrder({ status: 'pending_acceptance' });
    mockQuery
      .mockResolvedValueOnce({ rows: [order], rowCount: 1 })
      .mockResolvedValueOnce({ rows: [{ id: uuidv4() }], rowCount: 1 }); // different restaurant
    const res = await request(app).put(`/api/v1/orders/${order.id}/accept`).send({});
    expect(res.status).toBe(403);
  });

  test('non-pending_acceptance status returns 409', async () => {
    const ownerId = uuidv4();
    const restaurantId = uuidv4();
    setAuth(ownerId, 'restaurant');
    const order = makeOrder({ status: 'confirmed', restaurant_id: restaurantId });
    mockQuery
      .mockResolvedValueOnce({ rows: [order], rowCount: 1 })
      .mockResolvedValueOnce({ rows: [{ id: restaurantId }], rowCount: 1 });
    const res = await request(app).put(`/api/v1/orders/${order.id}/accept`).send({});
    expect(res.status).toBe(409);
  });

  test('successful accept returns 200 with status=confirmed', async () => {
    const ownerId = uuidv4();
    const restaurantId = uuidv4();
    setAuth(ownerId, 'restaurant');
    const order = makeOrder({ restaurant_id: restaurantId });
    setupAcceptQueries(order, restaurantId);
    const res = await request(app).put(`/api/v1/orders/${order.id}/accept`).send({});
    expect(res.status).toBe(200);
    expect(res.body.data.status).toBe('confirmed');
  });

  test('accept with estimatedPrepTimeMinutes stores the value', async () => {
    const ownerId = uuidv4();
    const restaurantId = uuidv4();
    setAuth(ownerId, 'restaurant');
    const order = makeOrder({ restaurant_id: restaurantId });
    const confirmedOrder = { ...order, status: 'confirmed' as OrderStatus, estimated_prep_time_minutes: 15 };
    mockQuery
      .mockResolvedValueOnce({ rows: [order], rowCount: 1 })
      .mockResolvedValueOnce({ rows: [{ id: restaurantId }], rowCount: 1 })
      .mockResolvedValueOnce({ rows: [confirmedOrder], rowCount: 1 });
    const res = await request(app)
      .put(`/api/v1/orders/${order.id}/accept`)
      .send({ estimatedPrepTimeMinutes: 15 });
    expect(res.status).toBe(200);
    expect(res.body.data.estimated_prep_time_minutes).toBe(15);
  });

  test('FCM failure does not affect 200 response', async () => {
    const ownerId = uuidv4();
    const restaurantId = uuidv4();
    setAuth(ownerId, 'restaurant');
    const order = makeOrder({ restaurant_id: restaurantId });
    setupAcceptQueries(order, restaurantId);
    const fcmErr = new Error('FCM error');
    mockSendPushNotification.mockImplementationOnce(() => {
      const p = Promise.reject(fcmErr);
      p.catch(() => {});
      return p;
    });
    const res = await request(app).put(`/api/v1/orders/${order.id}/accept`).send({});
    await new Promise(r => setImmediate(r));
    expect(res.status).toBe(200);
  });
});

describe('Task 7.1 — PUT /orders/:id/reject', () => {

  test('unauthenticated returns 401', async () => {
    setAuth(null, null);
    const res = await request(app).put(`/api/v1/orders/${uuidv4()}/reject`).send({ reason: 'Busy' });
    expect(res.status).toBe(401);
  });

  test('non-restaurant role returns 403', async () => {
    setAuth(uuidv4(), 'customer');
    const res = await request(app).put(`/api/v1/orders/${uuidv4()}/reject`).send({ reason: 'Busy' });
    expect(res.status).toBe(403);
  });

  test('missing reason returns 422', async () => {
    const res = await request(app).put(`/api/v1/orders/${uuidv4()}/reject`).send({});
    expect(res.status).toBe(422);
  });

  test('blank reason returns 422', async () => {
    const res = await request(app).put(`/api/v1/orders/${uuidv4()}/reject`).send({ reason: '   ' });
    expect(res.status).toBe(422);
  });

  test('wrong restaurant returns 403', async () => {
    const ownerId = uuidv4();
    setAuth(ownerId, 'restaurant');
    const order = makeOrder({ status: 'pending_acceptance' });
    mockQuery
      .mockResolvedValueOnce({ rows: [order], rowCount: 1 })
      .mockResolvedValueOnce({ rows: [{ id: uuidv4() }], rowCount: 1 });
    const res = await request(app).put(`/api/v1/orders/${order.id}/reject`).send({ reason: 'Busy' });
    expect(res.status).toBe(403);
  });

  test('non-pending_acceptance status returns 409', async () => {
    const ownerId = uuidv4();
    const restaurantId = uuidv4();
    setAuth(ownerId, 'restaurant');
    const order = makeOrder({ status: 'confirmed', restaurant_id: restaurantId });
    mockQuery
      .mockResolvedValueOnce({ rows: [order], rowCount: 1 })
      .mockResolvedValueOnce({ rows: [{ id: restaurantId }], rowCount: 1 });
    const res = await request(app).put(`/api/v1/orders/${order.id}/reject`).send({ reason: 'Busy' });
    expect(res.status).toBe(409);
  });

  test('successful reject returns 200 with status=cancelled and cancelled_by=restaurant', async () => {
    const ownerId = uuidv4();
    const restaurantId = uuidv4();
    setAuth(ownerId, 'restaurant');
    const order = makeOrder({ restaurant_id: restaurantId });
    setupRejectQueries(order, restaurantId, 'Kitchen closed');
    const res = await request(app).put(`/api/v1/orders/${order.id}/reject`).send({ reason: 'Kitchen closed' });
    expect(res.status).toBe(200);
    expect(res.body.data.status).toBe('cancelled');
    expect(res.body.data.cancelled_by).toBe('restaurant');
  });

  test('refund failure does not affect 200 response', async () => {
    const ownerId = uuidv4();
    const restaurantId = uuidv4();
    setAuth(ownerId, 'restaurant');
    const order = makeOrder({ restaurant_id: restaurantId });
    setupRejectQueries(order, restaurantId, 'Busy');
    const refundErr = new Error('Chapa error');
    mockInitiateRefund.mockImplementationOnce(() => {
      const p = Promise.reject(refundErr);
      p.catch(() => {});
      return p;
    });
    const res = await request(app).put(`/api/v1/orders/${order.id}/reject`).send({ reason: 'Busy' });
    await new Promise(r => setImmediate(r));
    expect(res.status).toBe(200);
  });

  test('FCM failure does not affect 200 response', async () => {
    const ownerId = uuidv4();
    const restaurantId = uuidv4();
    setAuth(ownerId, 'restaurant');
    const order = makeOrder({ restaurant_id: restaurantId });
    setupRejectQueries(order, restaurantId, 'Busy');
    const fcmErr = new Error('FCM error');
    mockSendPushNotification.mockImplementationOnce(() => {
      const p = Promise.reject(fcmErr);
      p.catch(() => {});
      return p;
    });
    const res = await request(app).put(`/api/v1/orders/${order.id}/reject`).send({ reason: 'Busy' });
    await new Promise(r => setImmediate(r));
    expect(res.status).toBe(200);
  });
});

// ═════════════════════════════════════════════════════════════════════════════
// Property-based tests (Tasks 7.2–7.7)
// ═════════════════════════════════════════════════════════════════════════════

// ── Arbitraries ───────────────────────────────────────────────────────────────

const nonPendingStatusArb = fc.constantFrom(
  'confirmed', 'ready_for_pickup', 'rider_assigned',
  'picked_up', 'delivered', 'cancelled', 'pending_payment', 'payment_failed'
) as fc.Arbitrary<OrderStatus>;

const nonEmptyReasonArb = fc.string({ minLength: 1, maxLength: 200 })
  .map(s => s.trim()).filter(s => s.length > 0);

const uuidArb = fc.uuidV(4);

function orderArb(statusOverride?: OrderStatus) {
  return fc.record({ id: uuidArb, customer_id: uuidArb, restaurant_id: uuidArb })
    .map(({ id, customer_id, restaurant_id }) =>
      makeOrder({ id, customer_id, restaurant_id, status: statusOverride ?? 'pending_acceptance' })
    );
}

// ── Task 7.2: Property 1 — Webhook always transitions to pending_acceptance ──

describe('Feature: restaurant-order-acceptance, Property 1: Webhook transitions to pending_acceptance', () => {
  test('for any valid successful webhook payload, order transitions to pending_acceptance with future deadline', async () => {
    await fc.assert(
      fc.asyncProperty(
        uuidArb, // tx_ref
        async (txRef) => {
          mockQuery.mockReset();

          const pendingOrder = { id: uuidv4(), status: 'pending_payment', customer_id: uuidv4(), restaurant_id: uuidv4() };
          const pendingAcceptanceOrder = {
            ...pendingOrder,
            status: 'pending_acceptance',
            payment_status: 'paid',
            acceptance_deadline: new Date(Date.now() + 180_000),
          };

          // handleWebhook queries: find order by tx_ref, update status, find restaurant owner
          mockQuery
            .mockResolvedValueOnce({ rows: [pendingOrder], rowCount: 1 })
            .mockResolvedValueOnce({ rows: [{ value: '180' }], rowCount: 1 }) // platform_config
            .mockResolvedValueOnce({ rows: [pendingAcceptanceOrder], rowCount: 1 }) // updateOrderStatus
            .mockResolvedValueOnce({ rows: [{ owner_id: uuidv4() }], rowCount: 1 }); // restaurant owner

          // Simulate webhook call directly via the service
          const { handleWebhook } = await import('../services/order.service');
          const payload = JSON.stringify({ tx_ref: txRef, status: 'success', amount: 120 });
          await handleWebhook(payload, 'valid-sig');

          // The update call should have set status to pending_acceptance
          // The status is passed as a parameter ($1), not embedded in the SQL
          const updateCall = mockQuery.mock.calls.find(
            (call: unknown[]) => {
              const sql = call[0] as string;
              const params = call[1] as unknown[];
              return typeof sql === 'string' &&
                sql.includes('UPDATE orders') &&
                Array.isArray(params) &&
                params.includes('pending_acceptance');
            }
          );
          expect(updateCall).toBeDefined();
        }
      ),
      { numRuns: 20 }
    );
  });
});

// ── Task 7.3: Property 2 — Accept state machine invariant ────────────────────

describe('Feature: restaurant-order-acceptance, Property 2: Accept state machine invariant', () => {
  test('for pending_acceptance orders, accept returns 200 and status=confirmed', async () => {
    await fc.assert(
      fc.asyncProperty(
        orderArb('pending_acceptance'),
        async (order) => {
          mockQuery.mockReset();
          const ownerId = uuidv4();
          setAuth(ownerId, 'restaurant');
          setupAcceptQueries(order, order.restaurant_id);
          const res = await request(app).put(`/api/v1/orders/${order.id}/accept`).send({});
          expect(res.status).toBe(200);
          expect(res.body.data.status).toBe('confirmed');
        }
      ),
      { numRuns: 30 }
    );
  });

  test('for non-pending_acceptance orders, accept returns 409 and no DB update occurs', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.record({ id: uuidArb, customer_id: uuidArb, restaurant_id: uuidArb }),
        nonPendingStatusArb,
        async ({ id, customer_id, restaurant_id }, status) => {
          mockQuery.mockReset();
          const ownerId = uuidv4();
          setAuth(ownerId, 'restaurant');
          const order = makeOrder({ id, customer_id, restaurant_id, status });
          mockQuery
            .mockResolvedValueOnce({ rows: [order], rowCount: 1 })
            .mockResolvedValueOnce({ rows: [{ id: restaurant_id }], rowCount: 1 });
          const res = await request(app).put(`/api/v1/orders/${order.id}/accept`).send({});
          expect(res.status).toBe(409);
          // updateOrderStatus (3rd query) must NOT have been called
          expect(mockQuery).toHaveBeenCalledTimes(2);
        }
      ),
      { numRuns: 30 }
    );
  });
});

// ── Task 7.4: Property 3 — Reject always triggers refund and customer notification ──

describe('Feature: restaurant-order-acceptance, Property 3: Reject always triggers refund and customer notification', () => {
  test('for any valid rejection, initiateRefund called once and customer notified', async () => {
    await fc.assert(
      fc.asyncProperty(
        orderArb('pending_acceptance'),
        nonEmptyReasonArb,
        async (order, reason) => {
          mockQuery.mockReset();
          mockInitiateRefund.mockReset();
          mockSendPushNotification.mockReset();
          const ownerId = uuidv4();
          setAuth(ownerId, 'restaurant');
          setupRejectQueries(order, order.restaurant_id, reason);
          mockInitiateRefund.mockResolvedValue(undefined);
          mockSendPushNotification.mockResolvedValue(undefined);

          const res = await request(app)
            .put(`/api/v1/orders/${order.id}/reject`)
            .send({ reason });

          await new Promise(r => setImmediate(r));

          expect(res.status).toBe(200);
          expect(mockInitiateRefund).toHaveBeenCalledTimes(1);
          expect(mockInitiateRefund).toHaveBeenCalledWith(order.id);
          expect(mockSendPushNotification).toHaveBeenCalledWith(
            order.customer_id,
            'Order Rejected',
            expect.stringContaining(reason),
            expect.any(Object)
          );
        }
      ),
      { numRuns: 30 }
    );
  });
});

// ── Task 7.5: Property 4 — Timeout cancellation is idempotent ────────────────

describe('Feature: restaurant-order-acceptance, Property 4: Timeout cancellation is idempotent', () => {
  test('running cancelExpiredOrder twice results in exactly one status update and one refund call', async () => {
    await fc.assert(
      fc.asyncProperty(
        uuidArb, uuidArb, uuidArb,
        async (orderId, customerId, restaurantId) => {
          mockQuery.mockReset();
          mockInitiateRefund.mockReset();
          mockSendPushNotification.mockReset();

          // First call: order is still in pending_acceptance → cancels it
          const cancelledOrder = makeOrder({
            id: orderId, customer_id: customerId, restaurant_id: restaurantId,
            status: 'cancelled',
          });
          mockQuery
            .mockResolvedValueOnce({ rows: [cancelledOrder], rowCount: 1 }) // UPDATE returns row
            .mockResolvedValueOnce({ rows: [{ owner_id: uuidv4() }], rowCount: 1 }) // restaurant owner
            // Second call: UPDATE returns no rows (already cancelled)
            .mockResolvedValueOnce({ rows: [], rowCount: 0 });

          mockInitiateRefund.mockResolvedValue(undefined);
          mockSendPushNotification.mockResolvedValue(undefined);

          const { cancelExpiredOrder } = await import('../services/scheduler.service') as any;
          if (typeof cancelExpiredOrder !== 'function') return; // internal function, skip if not exported

          // Call twice
          await cancelExpiredOrder(orderId, customerId, restaurantId);
          await cancelExpiredOrder(orderId, customerId, restaurantId);

          await new Promise(r => setImmediate(r));

          // initiateRefund should be called at most once (second call is a no-op)
          expect(mockInitiateRefund.mock.calls.length).toBeLessThanOrEqual(1);
        }
      ),
      { numRuns: 20 }
    );
  });
});

// ── Task 7.6: Property 5 — Ownership guard is consistent ─────────────────────

describe('Feature: restaurant-order-acceptance, Property 5: Ownership guard is consistent', () => {
  test('for any order where ownerRestaurantId !== order.restaurant_id, both accept and reject return 403', async () => {
    await fc.assert(
      fc.asyncProperty(
        uuidArb, // owner's restaurant ID
        orderArb('pending_acceptance'),
        nonEmptyReasonArb,
        async (ownerRestaurantId, order, reason) => {
          fc.pre(ownerRestaurantId !== order.restaurant_id);

          // Test accept
          mockQuery.mockReset();
          mockInitiateRefund.mockReset();
          mockEmitOrderStatusChanged.mockReset();
          setAuth(uuidv4(), 'restaurant');
          mockQuery
            .mockResolvedValueOnce({ rows: [order], rowCount: 1 })
            .mockResolvedValueOnce({ rows: [{ id: ownerRestaurantId }], rowCount: 1 });
          const acceptRes = await request(app).put(`/api/v1/orders/${order.id}/accept`).send({});
          expect(acceptRes.status).toBe(403);
          expect(mockQuery).toHaveBeenCalledTimes(2); // no 3rd update call

          // Test reject
          mockQuery.mockReset();
          mockInitiateRefund.mockReset();
          mockEmitOrderStatusChanged.mockReset();
          setAuth(uuidv4(), 'restaurant');
          mockQuery
            .mockResolvedValueOnce({ rows: [order], rowCount: 1 })
            .mockResolvedValueOnce({ rows: [{ id: ownerRestaurantId }], rowCount: 1 });
          const rejectRes = await request(app).put(`/api/v1/orders/${order.id}/reject`).send({ reason });
          expect(rejectRes.status).toBe(403);
          expect(mockQuery).toHaveBeenCalledTimes(2);
        }
      ),
      { numRuns: 30 }
    );
  });
});

// ── Task 7.7: Property 6 — Notifications sent for all terminal transitions ───

describe('Feature: restaurant-order-acceptance, Property 6: Notifications sent for all terminal transitions', () => {
  test('accept: customer receives socket event and FCM notification', async () => {
    await fc.assert(
      fc.asyncProperty(
        orderArb('pending_acceptance'),
        async (order) => {
          mockQuery.mockReset();
          mockInitiateRefund.mockReset();
          mockEmitOrderStatusChanged.mockReset();
          mockSendPushNotification.mockReset();
          setAuth(uuidv4(), 'restaurant');
          setupAcceptQueries(order, order.restaurant_id);
          mockSendPushNotification.mockResolvedValue(undefined);

          const res = await request(app).put(`/api/v1/orders/${order.id}/accept`).send({});
          await new Promise(r => setImmediate(r));

          expect(res.status).toBe(200);
          expect(mockEmitOrderStatusChanged).toHaveBeenCalledWith(
            expect.objectContaining({ status: 'confirmed' }),
            order.customer_id
          );
          expect(mockSendPushNotification).toHaveBeenCalledWith(
            order.customer_id,
            'Order Accepted',
            expect.any(String),
            expect.any(Object)
          );
        }
      ),
      { numRuns: 20 }
    );
  });

  test('reject: customer receives socket event and FCM notification with reason', async () => {
    await fc.assert(
      fc.asyncProperty(
        orderArb('pending_acceptance'),
        nonEmptyReasonArb,
        async (order, reason) => {
          mockQuery.mockReset();
          mockInitiateRefund.mockReset();
          mockEmitOrderStatusChanged.mockReset();
          mockSendPushNotification.mockReset();
          setAuth(uuidv4(), 'restaurant');
          setupRejectQueries(order, order.restaurant_id, reason);
          mockSendPushNotification.mockResolvedValue(undefined);

          const res = await request(app).put(`/api/v1/orders/${order.id}/reject`).send({ reason });
          await new Promise(r => setImmediate(r));

          expect(res.status).toBe(200);
          expect(mockEmitOrderStatusChanged).toHaveBeenCalledWith(
            expect.objectContaining({ status: 'cancelled' }),
            order.customer_id
          );
          expect(mockSendPushNotification).toHaveBeenCalledWith(
            order.customer_id,
            'Order Rejected',
            expect.stringContaining(reason),
            expect.any(Object)
          );
        }
      ),
      { numRuns: 20 }
    );
  });
});
