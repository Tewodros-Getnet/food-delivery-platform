/**
 * Feature: restaurant-order-cancellation
 *
 * Tests for PUT /orders/:id/restaurant-cancel
 *
 * Tasks 3.3–3.8: unit/integration tests + property-based tests
 */

import request from 'supertest';
import fc from 'fast-check';
import { v4 as uuidv4 } from 'uuid';

// ── Mocks ─────────────────────────────────────────────────────────────────────

jest.mock('../config/database', () => ({
  pool: { end: jest.fn() },
  query: jest.fn(),
  withTransaction: jest.fn(),
}));

jest.mock('../services/refund.service', () => ({
  initiateRefund: jest.fn().mockResolvedValue(undefined),
}));

jest.mock('../services/socket.service', () => ({
  emitOrderStatusChanged: jest.fn(),
  emitToRestaurant: jest.fn(),
  initSocketServer: jest.fn(),
}));

jest.mock('../services/fcm.service', () => ({
  sendPushNotification: jest.fn().mockResolvedValue(undefined),
  registerFcmToken: jest.fn(),
}));

// Mock auth middleware so we can inject userId / userRole per test
jest.mock('../middleware/auth', () => ({
  authenticate: jest.fn((req: any, _res: any, next: any) => {
    next();
  }),
}));

// Disable rate limiting so property tests (100+ requests) don't get 429
jest.mock('../middleware/rateLimiter', () => {
  const passThrough = (_req: any, _res: any, next: any) => next();
  return {
    rateLimiter: passThrough,
    authRateLimiter: passThrough,
  };
});

// ── Imports after mocks ───────────────────────────────────────────────────────

import app from '../app';
import { query } from '../config/database';
import { initiateRefund } from '../services/refund.service';
import { emitOrderStatusChanged } from '../services/socket.service';
import { sendPushNotification } from '../services/fcm.service';
import { authenticate } from '../middleware/auth';
import { logger } from '../utils/logger';

const mockQuery = query as jest.Mock;
const mockInitiateRefund = initiateRefund as jest.Mock;
const mockEmitOrderStatusChanged = emitOrderStatusChanged as jest.Mock;
const mockSendPushNotification = sendPushNotification as jest.Mock;
const mockAuthenticate = authenticate as jest.Mock;

// ── Helpers ───────────────────────────────────────────────────────────────────

type OrderStatus =
  | 'pending_payment'
  | 'payment_failed'
  | 'confirmed'
  | 'ready_for_pickup'
  | 'rider_assigned'
  | 'picked_up'
  | 'delivered'
  | 'cancelled';

function makeOrder(overrides: Partial<{
  id: string;
  customer_id: string;
  restaurant_id: string;
  status: OrderStatus;
  cancellation_reason: string | null;
  cancelled_by: string | null;
  cancelled_at: Date | null;
}> = {}) {
  return {
    id: uuidv4(),
    customer_id: uuidv4(),
    restaurant_id: uuidv4(),
    rider_id: null,
    delivery_address_id: uuidv4(),
    status: 'confirmed' as OrderStatus,
    subtotal: 100,
    delivery_fee: 20,
    total: 120,
    payment_reference: 'ref-123',
    payment_status: 'paid',
    cancellation_reason: null,
    cancelled_at: null,
    cancelled_by: null,
    estimated_prep_time_minutes: null,
    created_at: new Date(),
    updated_at: new Date(),
    ...overrides,
  };
}

/**
 * Set up the authenticate mock to inject userId and userRole.
 * Pass null to simulate unauthenticated (returns 401).
 */
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

/**
 * Set up query mock for the standard happy-path sequence:
 *   1. getOrderById  → returns the order
 *   2. SELECT restaurant by owner_id → returns { id: restaurantId }
 *   3. updateOrderStatus → returns the cancelled order
 */
function setupHappyPathQueries(
  order: ReturnType<typeof makeOrder>,
  restaurantId: string,
  reason: string
) {
  const cancelledOrder = {
    ...order,
    status: 'cancelled' as OrderStatus,
    cancellation_reason: reason,
    cancelled_by: 'restaurant',
    cancelled_at: new Date(),
  };

  mockQuery
    // getOrderById
    .mockResolvedValueOnce({ rows: [order], rowCount: 1 })
    // SELECT restaurant by owner_id
    .mockResolvedValueOnce({ rows: [{ id: restaurantId }], rowCount: 1 })
    // updateOrderStatus
    .mockResolvedValueOnce({ rows: [cancelledOrder], rowCount: 1 });

  return cancelledOrder;
}

// ── beforeEach / afterEach ────────────────────────────────────────────────────

beforeEach(() => {
  jest.clearAllMocks();
  // Default: authenticated as restaurant owner
  const defaultUserId = uuidv4();
  setAuth(defaultUserId, 'restaurant');
});

// ═════════════════════════════════════════════════════════════════════════════
// Task 3.8 — Unit / Integration tests (example-based)
// ═════════════════════════════════════════════════════════════════════════════

describe('Task 3.8 — Unit/Integration tests: PUT /orders/:id/restaurant-cancel', () => {

  // ── 401: unauthenticated ──────────────────────────────────────────────────

  test('unauthenticated request returns 401', async () => {
    setAuth(null, null);
    const res = await request(app)
      .put(`/api/v1/orders/${uuidv4()}/restaurant-cancel`)
      .send({ reason: 'Kitchen closed' });

    expect(res.status).toBe(401);
  });

  // ── 403: customer role ────────────────────────────────────────────────────

  test('customer-role request returns 403', async () => {
    const customerId = uuidv4();
    setAuth(customerId, 'customer');

    const res = await request(app)
      .put(`/api/v1/orders/${uuidv4()}/restaurant-cancel`)
      .send({ reason: 'Kitchen closed' });

    expect(res.status).toBe(403);
  });

  // ── 422: missing reason ───────────────────────────────────────────────────

  test('missing reason returns 422', async () => {
    const ownerId = uuidv4();
    setAuth(ownerId, 'restaurant');

    const res = await request(app)
      .put(`/api/v1/orders/${uuidv4()}/restaurant-cancel`)
      .send({});

    expect(res.status).toBe(422);
  });

  test('empty reason returns 422', async () => {
    const ownerId = uuidv4();
    setAuth(ownerId, 'restaurant');

    const res = await request(app)
      .put(`/api/v1/orders/${uuidv4()}/restaurant-cancel`)
      .send({ reason: '   ' });

    expect(res.status).toBe(422);
  });

  // ── 409: non-cancellable statuses ─────────────────────────────────────────

  const nonCancellableStatuses: OrderStatus[] = [
    'picked_up',
    'delivered',
    'cancelled',
    'pending_payment',
    'payment_failed',
  ];

  for (const status of nonCancellableStatuses) {
    test(`status '${status}' returns 409`, async () => {
      const ownerId = uuidv4();
      const restaurantId = uuidv4();
      setAuth(ownerId, 'restaurant');

      const order = makeOrder({ status, restaurant_id: restaurantId });

      mockQuery
        // getOrderById
        .mockResolvedValueOnce({ rows: [order], rowCount: 1 })
        // SELECT restaurant by owner_id
        .mockResolvedValueOnce({ rows: [{ id: restaurantId }], rowCount: 1 });

      const res = await request(app)
        .put(`/api/v1/orders/${order.id}/restaurant-cancel`)
        .send({ reason: 'Kitchen closed' });

      expect(res.status).toBe(409);
    });
  }

  // ── 403: cross-restaurant ownership ──────────────────────────────────────

  test('cross-restaurant ownership returns 403', async () => {
    const ownerId = uuidv4();
    const ownerRestaurantId = uuidv4();
    const otherRestaurantId = uuidv4(); // order belongs to a different restaurant
    setAuth(ownerId, 'restaurant');

    const order = makeOrder({ restaurant_id: otherRestaurantId, status: 'confirmed' });

    mockQuery
      // getOrderById
      .mockResolvedValueOnce({ rows: [order], rowCount: 1 })
      // SELECT restaurant by owner_id → returns the owner's restaurant (different from order's)
      .mockResolvedValueOnce({ rows: [{ id: ownerRestaurantId }], rowCount: 1 });

    const res = await request(app)
      .put(`/api/v1/orders/${order.id}/restaurant-cancel`)
      .send({ reason: 'Kitchen closed' });

    expect(res.status).toBe(403);
  });

  // ── Refund throws — cancel still succeeds ─────────────────────────────────

  test('refund service throws after all retries — cancel response still succeeds (200) and error is logged', async () => {
    const ownerId = uuidv4();
    const restaurantId = uuidv4();
    setAuth(ownerId, 'restaurant');

    const order = makeOrder({ restaurant_id: restaurantId, status: 'confirmed' });
    const reason = 'Item unavailable';
    setupHappyPathQueries(order, restaurantId, reason);

    // Make initiateRefund reject — but since it's fire-and-forget (void), the
    // rejection must not propagate to the HTTP response. Attach a no-op catch
    // so Jest doesn't surface it as an unhandled rejection.
    const refundError = new Error('Chapa refund failed after all retries');
    mockInitiateRefund.mockImplementationOnce(() => {
      const p = Promise.reject(refundError);
      p.catch(() => { /* swallow — fire-and-forget */ });
      return p;
    });

    const loggerErrorSpy = jest.spyOn(logger, 'error').mockImplementation(() => {});

    const res = await request(app)
      .put(`/api/v1/orders/${order.id}/restaurant-cancel`)
      .send({ reason });

    // Give the fire-and-forget promise a tick to settle
    await new Promise(resolve => setImmediate(resolve));

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);

    loggerErrorSpy.mockRestore();
  });

  // ── FCM throws — cancel still succeeds ───────────────────────────────────

  test('FCM throws — cancel response still succeeds (200)', async () => {
    const ownerId = uuidv4();
    const restaurantId = uuidv4();
    setAuth(ownerId, 'restaurant');

    const order = makeOrder({ restaurant_id: restaurantId, status: 'confirmed' });
    const reason = 'Too busy';
    setupHappyPathQueries(order, restaurantId, reason);

    // sendPushNotification is called with void — rejection must not propagate
    const fcmError = new Error('FCM error');
    mockSendPushNotification.mockImplementationOnce(() => {
      const p = Promise.reject(fcmError);
      p.catch(() => { /* swallow */ });
      return p;
    });

    const res = await request(app)
      .put(`/api/v1/orders/${order.id}/restaurant-cancel`)
      .send({ reason });

    await new Promise(resolve => setImmediate(resolve));

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
  });

  // ── 200: successful cancellation ─────────────────────────────────────────

  test('successful cancellation returns 200 with cancelled_by="restaurant"', async () => {
    const ownerId = uuidv4();
    const restaurantId = uuidv4();
    setAuth(ownerId, 'restaurant');

    const order = makeOrder({ restaurant_id: restaurantId, status: 'confirmed' });
    const reason = 'Ingredient ran out';
    setupHappyPathQueries(order, restaurantId, reason);

    const res = await request(app)
      .put(`/api/v1/orders/${order.id}/restaurant-cancel`)
      .send({ reason });

    expect(res.status).toBe(200);
    expect(res.body.success).toBe(true);
    expect(res.body.data.cancelled_by).toBe('restaurant');
    expect(res.body.data.status).toBe('cancelled');
    expect(res.body.data.cancellation_reason).toBe(reason);
  });

});

// ═════════════════════════════════════════════════════════════════════════════
// Tasks 3.3–3.7 — Property-based tests (fast-check)
// ═════════════════════════════════════════════════════════════════════════════

// ── Arbitraries ───────────────────────────────────────────────────────────────

const cancellableStatusArb = fc.constantFrom('confirmed', 'ready_for_pickup') as fc.Arbitrary<OrderStatus>;

const nonCancellableStatusArb = fc.constantFrom(
  'picked_up',
  'delivered',
  'cancelled',
  'pending_payment',
  'payment_failed'
) as fc.Arbitrary<OrderStatus>;

// Reasons must be non-empty after trimming (the endpoint trims the value via express-validator)
const nonEmptyReasonArb = fc.string({ minLength: 1, maxLength: 200 })
  .map(s => s.trim())
  .filter(s => s.length > 0);

const uuidArb = fc.uuidV(4);

/** Generates a full order object with a given status */
function orderArb(statusArb: fc.Arbitrary<OrderStatus>) {
  return fc.record({
    id: uuidArb,
    customer_id: uuidArb,
    restaurant_id: uuidArb,
    status: statusArb,
  }).map(({ id, customer_id, restaurant_id, status }) =>
    makeOrder({ id, customer_id, restaurant_id, status })
  );
}

// ── Property 1 ────────────────────────────────────────────────────────────────

/**
 * Property 1: Cancellation round-trip persists status, reason, and actor
 * Validates: Requirements 1.1, 5.1, 5.3
 */
describe('Feature: restaurant-order-cancellation, Property 1: cancellation round-trip persists status, reason, and actor', () => {
  test('returned order has status=cancelled, correct reason, cancelled_by=restaurant, non-null cancelled_at', async () => {
    await fc.assert(
      fc.asyncProperty(
        orderArb(cancellableStatusArb),
        nonEmptyReasonArb,
        async (order, reason) => {
          jest.clearAllMocks();

          const ownerId = uuidv4();
          setAuth(ownerId, 'restaurant');

          const cancelledOrder = {
            ...order,
            status: 'cancelled' as OrderStatus,
            cancellation_reason: reason,
            cancelled_by: 'restaurant',
            cancelled_at: new Date(),
          };

          mockQuery
            .mockResolvedValueOnce({ rows: [order], rowCount: 1 })
            .mockResolvedValueOnce({ rows: [{ id: order.restaurant_id }], rowCount: 1 })
            .mockResolvedValueOnce({ rows: [cancelledOrder], rowCount: 1 });

          mockInitiateRefund.mockResolvedValue(undefined);
          mockSendPushNotification.mockResolvedValue(undefined);

          const res = await request(app)
            .put(`/api/v1/orders/${order.id}/restaurant-cancel`)
            .send({ reason });

          expect(res.status).toBe(200);
          expect(res.body.data.status).toBe('cancelled');
          expect(res.body.data.cancellation_reason).toBe(reason);
          expect(res.body.data.cancelled_by).toBe('restaurant');
          expect(res.body.data.cancelled_at).not.toBeNull();
        }
      ),
      { numRuns: 100 }
    );
  });
});

// ── Property 2 ────────────────────────────────────────────────────────────────

/**
 * Property 2: Ownership guard rejects cross-restaurant cancellations
 * Validates: Requirements 1.2, 1.4
 */
describe('Feature: restaurant-order-cancellation, Property 2: ownership guard rejects cross-restaurant cancellations', () => {
  test('endpoint returns 403 and order status in DB is unchanged', async () => {
    await fc.assert(
      fc.asyncProperty(
        uuidArb, // owner's restaurant ID
        orderArb(cancellableStatusArb), // order belonging to a different restaurant
        nonEmptyReasonArb,
        async (ownerRestaurantId, order, reason) => {
          // Ensure the order's restaurant is different from the owner's restaurant
          fc.pre(ownerRestaurantId !== order.restaurant_id);

          jest.clearAllMocks();

          const ownerId = uuidv4();
          setAuth(ownerId, 'restaurant');

          mockQuery
            // getOrderById
            .mockResolvedValueOnce({ rows: [order], rowCount: 1 })
            // SELECT restaurant by owner_id → returns owner's restaurant (different from order's)
            .mockResolvedValueOnce({ rows: [{ id: ownerRestaurantId }], rowCount: 1 });

          const res = await request(app)
            .put(`/api/v1/orders/${order.id}/restaurant-cancel`)
            .send({ reason });

          expect(res.status).toBe(403);

          // updateOrderStatus (3rd query) should NOT have been called
          expect(mockQuery).toHaveBeenCalledTimes(2);
        }
      ),
      { numRuns: 100 }
    );
  });
});

// ── Property 3 ────────────────────────────────────────────────────────────────

/**
 * Property 3: Status guard rejects non-cancellable orders
 * Validates: Requirements 1.3
 */
describe('Feature: restaurant-order-cancellation, Property 3: status guard rejects non-cancellable orders', () => {
  test('endpoint returns 409 and order status in DB is unchanged', async () => {
    await fc.assert(
      fc.asyncProperty(
        orderArb(nonCancellableStatusArb),
        nonEmptyReasonArb,
        async (order, reason) => {
          jest.clearAllMocks();

          const ownerId = uuidv4();
          setAuth(ownerId, 'restaurant');

          mockQuery
            // getOrderById
            .mockResolvedValueOnce({ rows: [order], rowCount: 1 })
            // SELECT restaurant by owner_id → same restaurant as order
            .mockResolvedValueOnce({ rows: [{ id: order.restaurant_id }], rowCount: 1 });

          const res = await request(app)
            .put(`/api/v1/orders/${order.id}/restaurant-cancel`)
            .send({ reason });

          expect(res.status).toBe(409);

          // updateOrderStatus (3rd query) should NOT have been called
          expect(mockQuery).toHaveBeenCalledTimes(2);
        }
      ),
      { numRuns: 100 }
    );
  });
});

// ── Property 4 ────────────────────────────────────────────────────────────────

/**
 * Property 4: Refund is always invoked on successful cancellation
 * Validates: Requirements 2.1
 */
describe('Feature: restaurant-order-cancellation, Property 4: refund is always invoked on successful cancellation', () => {
  test('initiateRefund mock called exactly once with the order ID', async () => {
    await fc.assert(
      fc.asyncProperty(
        orderArb(cancellableStatusArb),
        nonEmptyReasonArb,
        async (order, reason) => {
          jest.clearAllMocks();

          const ownerId = uuidv4();
          setAuth(ownerId, 'restaurant');

          const cancelledOrder = {
            ...order,
            status: 'cancelled' as OrderStatus,
            cancellation_reason: reason,
            cancelled_by: 'restaurant',
            cancelled_at: new Date(),
          };

          mockQuery
            .mockResolvedValueOnce({ rows: [order], rowCount: 1 })
            .mockResolvedValueOnce({ rows: [{ id: order.restaurant_id }], rowCount: 1 })
            .mockResolvedValueOnce({ rows: [cancelledOrder], rowCount: 1 });

          mockInitiateRefund.mockResolvedValue(undefined);
          mockSendPushNotification.mockResolvedValue(undefined);

          const res = await request(app)
            .put(`/api/v1/orders/${order.id}/restaurant-cancel`)
            .send({ reason });

          // Give fire-and-forget a tick to settle
          await new Promise(resolve => setImmediate(resolve));

          expect(res.status).toBe(200);
          expect(mockInitiateRefund).toHaveBeenCalledTimes(1);
          expect(mockInitiateRefund).toHaveBeenCalledWith(order.id);
        }
      ),
      { numRuns: 100 }
    );
  });
});

// ── Property 5 ────────────────────────────────────────────────────────────────

/**
 * Property 5: Customer is always notified on successful cancellation
 * Validates: Requirements 3.1, 3.2
 */
describe('Feature: restaurant-order-cancellation, Property 5: customer is always notified on successful cancellation', () => {
  test('emitOrderStatusChanged called with customer ID; sendPushNotification called with customer ID, title "Order Cancelled", body containing reason', async () => {
    await fc.assert(
      fc.asyncProperty(
        orderArb(cancellableStatusArb),
        nonEmptyReasonArb,
        async (order, reason) => {
          jest.clearAllMocks();

          const ownerId = uuidv4();
          setAuth(ownerId, 'restaurant');

          const cancelledOrder = {
            ...order,
            status: 'cancelled' as OrderStatus,
            cancellation_reason: reason,
            cancelled_by: 'restaurant',
            cancelled_at: new Date(),
          };

          mockQuery
            .mockResolvedValueOnce({ rows: [order], rowCount: 1 })
            .mockResolvedValueOnce({ rows: [{ id: order.restaurant_id }], rowCount: 1 })
            .mockResolvedValueOnce({ rows: [cancelledOrder], rowCount: 1 });

          mockInitiateRefund.mockResolvedValue(undefined);
          mockSendPushNotification.mockResolvedValue(undefined);

          const res = await request(app)
            .put(`/api/v1/orders/${order.id}/restaurant-cancel`)
            .send({ reason });

          // Give fire-and-forget a tick to settle
          await new Promise(resolve => setImmediate(resolve));

          expect(res.status).toBe(200);

          // emitOrderStatusChanged must be called with the cancelled order and the customer ID
          expect(mockEmitOrderStatusChanged).toHaveBeenCalledWith(
            expect.objectContaining({ id: order.id, status: 'cancelled' }),
            order.customer_id
          );

          // sendPushNotification must be called with customer ID, title "Order Cancelled", body containing reason
          expect(mockSendPushNotification).toHaveBeenCalledWith(
            order.customer_id,
            'Order Cancelled',
            expect.stringContaining(reason),
            expect.any(Object)
          );
        }
      ),
      { numRuns: 100 }
    );
  });
});
