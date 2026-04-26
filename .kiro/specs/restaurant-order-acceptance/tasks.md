# Tasks

## Task List

- [x] 1. Database Migration
  - [x] 1.1 Create `database/migrations/009_order_acceptance.sql` — add `pending_acceptance` to the `orders.status` CHECK constraint, add `acceptance_deadline TIMESTAMP` column with a partial index on `(acceptance_deadline) WHERE status = 'pending_acceptance'`, and insert `order_acceptance_timeout_seconds = '180'` into `platform_config`

- [x] 2. Backend — Model & Types
  - [x] 2.1 Update `backend/src/models/order.model.ts` — add `'pending_acceptance'` to the `OrderStatus` union type and add `acceptance_deadline: Date | null` to the `Order` interface

- [x] 3. Backend — Order Service
  - [x] 3.1 Update `handleWebhook` in `backend/src/services/order.service.ts` — on payment success, transition order to `pending_acceptance` (not `confirmed`), set `acceptance_deadline` from `platform_config`, notify restaurant via FCM + socket, notify customer via socket
  - [x] 3.2 Add `getAcceptanceTimeoutSeconds()` helper in `backend/src/services/order.service.ts` — reads `order_acceptance_timeout_seconds` from `platform_config`, defaults to 180
  - [x] 3.3 Add `acceptOrder(orderId, restaurantOwnerId, estimatedPrepMinutes?)` function in `backend/src/services/order.service.ts` — validates ownership and status, transitions to `confirmed`, notifies customer via FCM + socket
  - [x] 3.4 Add `rejectOrder(orderId, restaurantOwnerId, reason)` function in `backend/src/services/order.service.ts` — validates ownership and status, transitions to `cancelled` with `cancelled_by='restaurant'`, fire-and-forget refund, notifies customer via FCM + socket

- [x] 4. Backend — Scheduler
  - [x] 4.1 Add `startAcceptanceTimeoutJob()` in `backend/src/services/scheduler.service.ts` — cron every 60 seconds, queries expired `pending_acceptance` orders, calls `cancelExpiredOrder` for each
  - [x] 4.2 Add `cancelExpiredOrder(orderId, customerId, restaurantId)` helper in `backend/src/services/scheduler.service.ts` — transitions to `cancelled`, fire-and-forget refund, notifies customer (FCM + socket) and restaurant owner (FCM)
  - [x] 4.3 Register `startAcceptanceTimeoutJob()` in `backend/src/index.ts` alongside the existing `startPaymentExpiryJob()`

- [x] 5. Backend — Socket Service
  - [x] 5.1 Add `emitOrderAcceptanceRequest(restaurantOwnerId, order)` helper in `backend/src/services/socket.service.ts` — emits `order:acceptance_request` event with order data and `acceptanceDeadline`, uses missed-event queue if owner is offline

- [x] 6. Backend — Controller & Routes
  - [x] 6.1 Create `backend/src/controllers/order-acceptance.controller.ts` — `acceptOrderHandler`, `rejectOrderHandler`, and `rejectValidation` (express-validator: `reason` required, non-empty after trim)
  - [x] 6.2 Register `PUT /orders/:id/accept` and `PUT /orders/:id/reject` routes in the existing orders router with `authenticate` middleware and `restaurant` RBAC guard

- [ ] 7. Backend — Tests
  - [ ] 7.1 Create `backend/src/tests/order-acceptance.test.ts` — unit/integration tests: unauthenticated returns 401, non-restaurant role returns 403, wrong restaurant returns 403, non-`pending_acceptance` status returns 409, missing reject reason returns 422, successful accept returns 200 with `status='confirmed'`, successful reject returns 200 with `status='cancelled'` and `cancelled_by='restaurant'`, refund failure does not affect HTTP 200 response, FCM failure does not affect HTTP 200 response
  - [ ] 7.2 Property 1 — Payment webhook always transitions to `pending_acceptance`: for any valid successful webhook payload, assert `order.status === 'pending_acceptance'` and `acceptance_deadline` is a future timestamp
  - [ ] 7.3 Property 2 — Accept state machine invariant: for orders in `pending_acceptance`, accept returns 200 and `status='confirmed'`; for orders in any other status, accept returns 409 and no DB update occurs
  - [ ] 7.4 Property 3 — Reject always triggers refund and customer notification: for any valid rejection, `initiateRefund` called once with order ID, `sendPushNotification` called with customer ID and title "Order Rejected"
  - [ ] 7.5 Property 4 — Timeout cancellation is idempotent: running `cancelExpiredOrder` twice on the same order results in exactly one status update and one refund call
  - [ ] 7.6 Property 5 — Ownership guard is consistent: for any order where `ownerRestaurantId !== order.restaurant_id`, both accept and reject return 403 and no DB update occurs
  - [ ] 7.7 Property 6 — Notifications sent for all terminal transitions: for accept, reject, and timeout paths, customer receives socket event and FCM notification for every valid order input

- [x] 8. Flutter — Restaurant App
  - [x] 8.1 Create `PendingAcceptanceOrderCard` widget — displays order summary, countdown timer driven by `acceptance_deadline`, "Accept" and "Reject" buttons with loading states
  - [x] 8.2 Create `RejectOrderDialog` widget — text field for rejection reason, submit button disabled until reason is non-empty, calls reject endpoint on confirm
  - [x] 8.3 Create `CountdownTimer` widget — takes a `DateTime deadline`, ticks every second, displays `MM:SS` remaining, shows "Expired" when elapsed
  - [x] 8.4 Create `PendingOrdersNotifier` state notifier — manages list of `pending_acceptance` orders, handles `order:acceptance_request` socket events to add orders, handles `order:status_changed` to remove/move orders
  - [x] 8.5 Update `OrdersScreen` — add "New Orders" section at top populated by `PendingOrdersNotifier`, visually distinct from confirmed orders section
  - [x] 8.6 Update restaurant app socket listener — handle `order:acceptance_request` event to add new pending orders to `PendingOrdersNotifier`

- [x] 9. Flutter — Customer App
  - [x] 9.1 Update `OrderTrackingScreen` — add `pending_acceptance` status display: "Waiting for restaurant confirmation" label with `CircularProgressIndicator`
  - [x] 9.2 Update customer app socket listener — handle `order:status_changed` from `pending_acceptance` to `cancelled`: show snackbar/dialog "Your order was not accepted. A refund has been initiated."
  - [x] 9.3 Update customer app order status mapping — ensure `pending_acceptance` is handled in all status display widgets and order history list items
