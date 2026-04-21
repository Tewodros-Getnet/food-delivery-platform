# Implementation Plan: Restaurant Order Cancellation

## Overview

Implement self-service order cancellation for restaurant owners across four layers: a database migration, a new backend endpoint, Flutter restaurant app UI, and an admin dashboard update. The backend reuses existing refund, socket, and FCM infrastructure. Tasks are ordered so each layer is independently testable before wiring everything together.

## Tasks

- [x] 1. Database migration — add `cancelled_by` column
  - Create `database/migrations/007_restaurant_cancellation.sql`
  - Add `cancelled_by VARCHAR(20) CHECK (cancelled_by IN ('customer', 'restaurant', 'admin'))` as a nullable column on the `orders` table
  - Add index `idx_orders_cancelled_by` on `orders(cancelled_by)`
  - _Requirements: 5.3_

- [x] 2. Backend — extend Order model and service
  - [x] 2.1 Add `cancelled_by` field to the `Order` interface in `backend/src/models/order.model.ts`
    - Type: `'customer' | 'restaurant' | 'admin' | null`
    - _Requirements: 5.3_

  - [x] 2.2 Extend `updateOrderStatus` in `backend/src/services/order.service.ts` to persist `cancelled_by`
    - Add `cancelled_by` to the `extra` parameter handling alongside the existing `cancellation_reason` and `cancelled_at` fields
    - _Requirements: 1.1, 5.3_

- [x] 3. Backend — implement the restaurant-cancel endpoint
  - [x] 3.1 Add the `PUT /orders/:id/restaurant-cancel` route in `backend/src/routes/orders.ts`
    - Apply `authenticate` and `authorize('restaurant')` middleware
    - Validate `reason` with `body('reason').trim().notEmpty()` (express-validator)
    - _Requirements: 1.5, 5.1, 5.2_

  - [x] 3.2 Implement the route handler logic
    - Fetch order by `:id`; return 404 if not found
    - Look up restaurant owned by `req.userId`; return 403 if none or if `order.restaurant_id !== restaurant.id`
    - Return 409 if `order.status` is not in `['confirmed', 'ready_for_pickup']`
    - Call `orderService.updateOrderStatus` with `status='cancelled'`, `cancelled_by='restaurant'`, `cancellation_reason`, and `cancelled_at`
    - Fire-and-forget `initiateRefund(order.id)` (do not await)
    - Call `emitOrderStatusChanged(updatedOrder, order.customer_id)`
    - Call `emitToRestaurant(req.userId, updatedOrder)`
    - Call `sendPushNotification(order.customer_id, 'Order Cancelled', reason, { type: 'order_cancelled', orderId })`
    - Return 200 with the updated order via `successResponse`
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.6, 2.1, 2.2, 3.1, 3.2, 5.1_

  - [x]* 3.3 Write property test — Property 1: cancellation round-trip persists status, reason, and actor
    - **Property 1: Cancellation round-trip persists status, reason, and actor**
    - **Validates: Requirements 1.1, 5.1, 5.3**
    - In `backend/src/tests/restaurant-cancel.test.ts` using fast-check
    - Generate random `orderId` (UUID), random non-empty `reason` string, order in `confirmed` or `ready_for_pickup`
    - Assert returned order has `status='cancelled'`, `cancellation_reason === reason`, `cancelled_by === 'restaurant'`, `cancelled_at` non-null

  - [x]* 3.4 Write property test — Property 2: ownership guard rejects cross-restaurant cancellations
    - **Property 2: Ownership guard rejects cross-restaurant cancellations**
    - **Validates: Requirements 1.2, 1.4**
    - Generate random restaurant owner ID and order belonging to a different restaurant
    - Assert endpoint returns 403 and order status in DB is unchanged

  - [x]* 3.5 Write property test — Property 3: status guard rejects non-cancellable orders
    - **Property 3: Status guard rejects non-cancellable orders**
    - **Validates: Requirements 1.3**
    - Generate random order with status drawn from `{picked_up, delivered, cancelled, pending_payment, payment_failed}`
    - Assert endpoint returns 409 and order status in DB is unchanged

  - [x]* 3.6 Write property test — Property 4: refund is always invoked on successful cancellation
    - **Property 4: Refund is always invoked on successful cancellation**
    - **Validates: Requirements 2.1**
    - Generate random valid cancellable order and reason
    - Assert `initiateRefund` mock was called exactly once with the order ID

  - [x]* 3.7 Write property test — Property 5: customer is always notified on successful cancellation
    - **Property 5: Customer is always notified on successful cancellation**
    - **Validates: Requirements 3.1, 3.2**
    - Generate random valid cancellable order and reason string
    - Assert `emitOrderStatusChanged` called with customer ID; `sendPushNotification` called with customer ID, title `"Order Cancelled"`, body containing the reason

  - [x]* 3.8 Write unit/integration tests for the restaurant-cancel endpoint
    - Unauthenticated request returns 401
    - Customer-role request returns 403
    - Missing `reason` returns 422
    - Each non-cancellable status returns 409
    - Refund service throws after all retries — cancel response still succeeds and error is logged
    - FCM throws — cancel response still succeeds
    - _Requirements: 1.3, 1.5, 2.2, 2.3, 3.4, 5.2_

- [x] 4. Checkpoint — backend tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 5. Backend — extend admin orders query
  - Add `cancelled_by` to the `SELECT` in the `GET /admin/orders` query in `backend/src/routes/` (or the relevant admin route file)
  - _Requirements: 5.3_

- [x] 6. Flutter restaurant app — extend OrderModel
  - Add nullable `cancellationReason` and `cancelledBy` fields to `OrderModel` in `order_model.dart`
  - Update `fromJson` / `toJson` to handle the new fields
  - _Requirements: 4.1, 4.6_

- [x] 7. Flutter restaurant app — add cancelOrder to OrderService
  - Add `cancelOrder(String orderId, String reason)` method to `order_service.dart`
  - Issue `PUT ${ApiConstants.orders}/$orderId/restaurant-cancel` with `{ 'reason': reason }` body
  - _Requirements: 4.3_

- [x] 8. Flutter restaurant app — cancel button and confirmation dialog in `_OrderCard`
  - [x] 8.1 Add conditional "Cancel Order" button to `_OrderCard` in `orders_screen.dart`
    - Show button when `order.status` is `confirmed` or `ready_for_pickup`
    - Hide button for all other statuses (including `rider_assigned`, `picked_up`)
    - _Requirements: 4.1, 4.6_

  - [x] 8.2 Implement the confirmation dialog with predefined reason picker
    - `AlertDialog` with `RadioListTile` group for: "Item unavailable", "Kitchen closed", "Too busy", "Ingredient ran out", "Other"
    - "Confirm" button disabled until a reason is selected
    - On confirm: call `orderService.cancelOrder`, show `CircularProgressIndicator`, disable interaction
    - On success: pop dialog, invoke `onCancelled()` callback, show `SnackBar("Order cancelled")`
    - On error: pop dialog, show `SnackBar` with API error message; leave order card unchanged
    - _Requirements: 4.2, 4.3, 4.4, 4.5_

  - [x]* 8.3 Write property test — Property 6: cancel button visibility matches order status
    - **Property 6: Cancel button visibility matches order status**
    - **Validates: Requirements 4.1, 4.6**
    - In `mobile/restaurant/test/order_card_cancel_test.dart`
    - Generate random `OrderModel` with status drawn from all possible statuses
    - Assert cancel button present iff status ∈ `{confirmed, ready_for_pickup}`

  - [x]* 8.4 Write property test — Property 7: successful cancellation removes order from active list
    - **Property 7: Successful cancellation removes order from active list**
    - **Validates: Requirements 4.4**
    - Generate random list of active orders, pick one to cancel
    - Assert after mock API success the cancelled order's ID is absent from the rendered list

  - [x]* 8.5 Write widget tests for the cancel dialog
    - Tapping cancel button opens dialog with 5 radio options
    - Confirm button disabled until a reason is selected
    - Loading indicator shown while API call is in flight
    - Error snackbar shown when API returns error; order card unchanged
    - _Requirements: 4.2, 4.3, 4.5_

- [x] 9. Admin dashboard — show `cancelled_by` badge in orders table
  - Add `cancelled_by` to the `Order` interface in `admin/src/app/dashboard/orders/page.tsx`
  - Add a "Cancelled By" column to the orders table, rendered only when `o.status === 'cancelled'`
  - Apply color badges: `customer` → blue, `restaurant` → orange, `admin` → red
  - _Requirements: 5.3_

- [x] 10. Final checkpoint — all tests pass
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for a faster MVP
- Each task references specific requirements for traceability
- Property tests use fast-check (backend) and the Flutter test framework (mobile)
- The backend endpoint reuses existing `refund.service.ts`, `socket.service.ts`, and `fcm.service.ts` without modification
- The `cancelled_by` column is nullable so existing rows and non-cancelled orders are unaffected
