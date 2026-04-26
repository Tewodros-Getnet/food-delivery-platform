# Design Document

## Overview

This document describes the technical design for the Restaurant Order Acceptance feature. The feature inserts a `pending_acceptance` status into the order lifecycle between payment success and `confirmed`, giving restaurants a 3-minute window to explicitly accept or reject each incoming order. Timeouts are handled by an extended scheduler job. The design reuses all existing infrastructure: Chapa webhooks, Socket.IO + FCM notifications, the refund service, and the scheduler service.

---

## Architecture

### Order Lifecycle — Updated State Machine

```
pending_payment
      │
      │  (Chapa webhook: success)
      ▼
pending_acceptance  ──── timeout (scheduler) ──────────────────────────────┐
      │                                                                     │
      │  (restaurant accepts)          (restaurant rejects)                 │
      ▼                                       ▼                             ▼
  confirmed                             cancelled                      cancelled
      │                              (refund + notify)             (refund + notify)
      │
  ready_for_pickup
      │
  rider_assigned
      │
   picked_up
      │
  delivered
```

The `payment_failed` and `cancelled` statuses remain terminal. No other transitions are affected.

---

## Database Changes

### Migration 009: Order Acceptance

```sql
-- 1. Add pending_acceptance to the status enum constraint
ALTER TABLE orders
  DROP CONSTRAINT IF EXISTS orders_status_check;

ALTER TABLE orders
  ADD CONSTRAINT orders_status_check CHECK (status IN (
    'pending_payment',
    'payment_failed',
    'pending_acceptance',
    'confirmed',
    'ready_for_pickup',
    'rider_assigned',
    'picked_up',
    'delivered',
    'cancelled'
  ));

-- 2. Add acceptance_deadline column
ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS acceptance_deadline TIMESTAMP;

CREATE INDEX IF NOT EXISTS idx_orders_acceptance_deadline
  ON orders(acceptance_deadline)
  WHERE status = 'pending_acceptance';

-- 3. Add acceptance_timeout_seconds to platform_config
INSERT INTO platform_config (key, value)
VALUES ('order_acceptance_timeout_seconds', '180')
ON CONFLICT (key) DO NOTHING;
```

### Updated `orders` Table Columns

| Column | Type | Notes |
|---|---|---|
| `status` | `VARCHAR(30)` | Now includes `pending_acceptance` |
| `acceptance_deadline` | `TIMESTAMP` | Set when order enters `pending_acceptance`; null otherwise |

---

## Backend Changes

### 1. `order.model.ts` — Updated `OrderStatus` Type

```typescript
export type OrderStatus =
  | 'pending_payment'
  | 'payment_failed'
  | 'pending_acceptance'   // NEW
  | 'confirmed'
  | 'ready_for_pickup'
  | 'rider_assigned'
  | 'picked_up'
  | 'delivered'
  | 'cancelled';

export interface Order {
  // ... existing fields ...
  acceptance_deadline: Date | null;  // NEW
}
```

### 2. `order.service.ts` — Webhook Handler Change

The `handleWebhook` function currently transitions `pending_payment` → `confirmed` on payment success. It will be updated to transition to `pending_acceptance` instead, and set `acceptance_deadline`.

```typescript
// In handleWebhook, on status === 'success':
const timeoutSeconds = await getAcceptanceTimeoutSeconds(); // reads platform_config
const accepted = await updateOrderStatus(order.id, 'pending_acceptance', {
  payment_status: 'paid',
  payment_reference: tx_ref,
  acceptance_deadline: new Date(Date.now() + timeoutSeconds * 1000),
});
// Notify restaurant: FCM + socket (existing emitToRestaurant)
// Notify customer: socket order:status_changed
```

Helper to read config:
```typescript
async function getAcceptanceTimeoutSeconds(): Promise<number> {
  const result = await query<{ value: string }>(
    "SELECT value FROM platform_config WHERE key = 'order_acceptance_timeout_seconds'"
  );
  return parseInt(result.rows[0]?.value ?? '180', 10);
}
```

### 3. New `order.service.ts` Functions

#### `acceptOrder(orderId, restaurantOwnerId, estimatedPrepMinutes?)`

```typescript
export async function acceptOrder(
  orderId: string,
  restaurantOwnerId: string,
  estimatedPrepMinutes?: number
): Promise<Order>
```

Logic:
1. Fetch order by ID — 404 if not found.
2. Fetch restaurant by `owner_id = restaurantOwnerId` — 403 if order's `restaurant_id` doesn't match.
3. If `order.status !== 'pending_acceptance'` — throw 409.
4. Call `updateOrderStatus(orderId, 'confirmed', { estimated_prep_time_minutes })`.
5. Emit `order:status_changed` to customer (socket + FCM "Order Accepted").
6. Emit `order:status_changed` to restaurant owner (socket).
7. Return updated order.

#### `rejectOrder(orderId, restaurantOwnerId, reason)`

```typescript
export async function rejectOrder(
  orderId: string,
  restaurantOwnerId: string,
  reason: string
): Promise<Order>
```

Logic:
1. Fetch order by ID — 404 if not found.
2. Fetch restaurant by `owner_id = restaurantOwnerId` — 403 if mismatch.
3. If `order.status !== 'pending_acceptance'` — throw 409.
4. Call `updateOrderStatus(orderId, 'cancelled', { cancellation_reason: reason, cancelled_by: 'restaurant', cancelled_at: new Date() })`.
5. Fire-and-forget: `void initiateRefund(orderId)`.
6. Emit `order:status_changed` to customer (socket + FCM "Order Rejected" with reason).
7. Emit `order:status_changed` to restaurant owner (socket).
8. Return updated order.

### 4. New API Endpoints

Both endpoints are added to the existing orders router.

#### `PUT /api/v1/orders/:id/accept`

- **Auth**: `authenticate` middleware (JWT required)
- **RBAC**: `restaurant` role only
- **Body**: `{ estimatedPrepTimeMinutes?: number }` (optional)
- **Responses**:
  - `200` — updated order object
  - `401` — unauthenticated
  - `403` — wrong role or wrong restaurant
  - `404` — order not found
  - `409` — order not in `pending_acceptance` status

#### `PUT /api/v1/orders/:id/reject`

- **Auth**: `authenticate` middleware (JWT required)
- **RBAC**: `restaurant` role only
- **Body**: `{ reason: string }` (required, non-empty after trim)
- **Responses**:
  - `200` — updated order object
  - `401` — unauthenticated
  - `403` — wrong role or wrong restaurant
  - `404` — order not found
  - `409` — order not in `pending_acceptance` status
  - `422` — missing or blank reason

### 5. New Controller — `order-acceptance.controller.ts`

```typescript
// PUT /orders/:id/accept
export async function acceptOrderHandler(req, res, next) { ... }

// PUT /orders/:id/reject
export async function rejectOrderHandler(req, res, next) { ... }

export const rejectValidation = [
  body('reason').trim().notEmpty().withMessage('Rejection reason is required'),
  validate,
];
```

### 6. `scheduler.service.ts` — Acceptance Timeout Job

A new cron job runs every 60 seconds:

```typescript
export function startAcceptanceTimeoutJob() {
  cron.schedule('* * * * *', async () => {
    try {
      const expired = await query<{ id: string; customer_id: string; restaurant_id: string }>(
        `SELECT id, customer_id, restaurant_id FROM orders
         WHERE status = 'pending_acceptance'
         AND acceptance_deadline < NOW()`
      );
      for (const order of expired.rows) {
        await cancelExpiredOrder(order.id, order.customer_id, order.restaurant_id);
      }
    } catch (err) {
      logger.error('Acceptance timeout job failed', { error: String(err) });
    }
  });
}
```

`cancelExpiredOrder` logic:
1. `updateOrderStatus(orderId, 'cancelled', { cancellation_reason: 'Restaurant did not respond in time', cancelled_by: 'restaurant', cancelled_at: new Date() })`.
2. Fire-and-forget: `void initiateRefund(orderId)`.
3. Emit `order:status_changed` to customer (socket + FCM "Order Cancelled").
4. Fetch restaurant `owner_id` and send FCM "Order Expired" to restaurant owner.

### 7. `socket.service.ts` — New Emit Helper

```typescript
export function emitOrderAcceptanceRequest(restaurantOwnerId: string, order: Order) {
  // Emits 'order:acceptance_request' event to the restaurant owner's socket room
  // Payload: { event: 'order:acceptance_request', data: { orderId, order, acceptanceDeadline } }
  // Falls back to missedEventQueue if owner is offline
}
```

---

## Flutter Changes

### Restaurant App

#### New Widget: `PendingAcceptanceOrderCard`

- Displays order summary (items, total, customer address).
- Shows a `CountdownTimer` widget that ticks down from `acceptance_deadline - now`.
- "Accept" button → calls `PUT /orders/:id/accept` → on success, moves card to active orders.
- "Reject" button → opens `RejectOrderDialog` (text field for reason) → calls `PUT /orders/:id/reject`.
- When countdown reaches zero, card shows "Expired" state; removed on next `order:status_changed` socket event.

#### Updated: `OrdersScreen`

- New "New Orders" section at the top, populated by orders with `status == 'pending_acceptance'`.
- Listens to `order:acceptance_request` socket event to add new cards in real time.
- Listens to `order:status_changed` to move/remove cards when status changes.

#### State Management

- `PendingOrdersNotifier` (Riverpod `StateNotifier` or equivalent) manages the list of `pending_acceptance` orders.
- Countdown timers are driven by a single `Timer.periodic` per screen, not per card, to avoid timer proliferation.

### Customer App

#### Updated: `OrderTrackingScreen`

- New status display for `pending_acceptance`: "Waiting for restaurant confirmation" with a `CircularProgressIndicator`.
- Listens to `order:status_changed` socket events to update UI reactively.
- On transition to `cancelled` from `pending_acceptance`: shows a `SnackBar` / dialog: "Your order was not accepted. A refund has been initiated."

---

## Notification Summary

| Event | Recipient | Channel | Title | Body |
|---|---|---|---|---|
| Payment success → `pending_acceptance` | Restaurant Owner | FCM + Socket | "New Order" | "You have a new order! Please accept or reject within 3 minutes." |
| Payment success → `pending_acceptance` | Customer | Socket | — | `order:status_changed` event only |
| Restaurant accepts → `confirmed` | Customer | FCM + Socket | "Order Accepted" | "Your order has been accepted and is being prepared!" |
| Restaurant rejects → `cancelled` | Customer | FCM + Socket | "Order Rejected" | "Your order was rejected: {reason}. A refund has been initiated." |
| Timeout → `cancelled` | Customer | FCM + Socket | "Order Cancelled" | "The restaurant did not respond in time. A refund has been initiated." |
| Timeout → `cancelled` | Restaurant Owner | FCM | "Order Expired" | "An order expired before you could respond." |

---

## Correctness Properties

### Property 1: Payment webhook always transitions to `pending_acceptance` (not `confirmed`)

For any successful Chapa webhook payload with a valid `tx_ref` referencing an order in `pending_payment` status, the resulting order status must be `pending_acceptance` and `acceptance_deadline` must be set to a future timestamp.

- **Pattern**: Invariant — the status after webhook processing is always `pending_acceptance`.
- **Test type**: Property-based test (fast-check) — vary `tx_ref`, `amount`, order data.

### Property 2: Accept transitions `pending_acceptance` → `confirmed` and only that

For any order in `pending_acceptance` status, a valid accept request from the owning restaurant must result in status `confirmed`. For any order NOT in `pending_acceptance` status, the accept request must return HTTP 409 and the status must remain unchanged.

- **Pattern**: State machine invariant — only valid transitions are permitted.
- **Test type**: Property-based test — vary order status, restaurant ownership.

### Property 3: Reject always triggers refund and customer notification

For any successful rejection (order in `pending_acceptance`, correct restaurant owner, non-empty reason), `initiateRefund` must be called exactly once with the order ID, and `sendPushNotification` must be called with the customer ID and title "Order Rejected".

- **Pattern**: Invariant — side effects are always triggered on success.
- **Test type**: Property-based test — vary order data and rejection reason.

### Property 4: Timeout cancellation is idempotent

Running the acceptance timeout job multiple times on the same expired order must result in exactly one cancellation and one refund initiation. Subsequent runs must not re-cancel or re-refund an already-cancelled order.

- **Pattern**: Idempotence — repeated application produces the same result.
- **Test type**: Property-based test — vary order IDs and deadline timestamps.

### Property 5: Ownership guard is consistent across accept and reject

For any order in `pending_acceptance` status, a request from a restaurant owner whose restaurant ID does not match the order's `restaurant_id` must return HTTP 403 for both accept and reject endpoints, and no status update must occur.

- **Pattern**: Invariant — authorization check is symmetric across both endpoints.
- **Test type**: Property-based test — vary restaurant IDs to ensure mismatch is always rejected.

### Property 6: Notification delivery for all terminal transitions from `pending_acceptance`

For every transition out of `pending_acceptance` (accept → `confirmed`, reject → `cancelled`, timeout → `cancelled`), the customer must receive both a socket event and an FCM notification. This must hold for any valid order data.

- **Pattern**: Invariant — notifications are always sent on status change.
- **Test type**: Property-based test — vary order data across all three transition paths.
