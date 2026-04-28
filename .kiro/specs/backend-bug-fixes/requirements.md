# Requirements Document

## Introduction

This document captures requirements for fixing nine confirmed backend data and logic bugs in the food delivery platform. The bugs span database growth, in-memory state loss, dispatch loop correctness, business rule enforcement, audit trail completeness, authentication security, refund observability, token hygiene, and schema completeness. Each requirement is derived from a specific confirmed defect and is written to be independently testable.

## Glossary

- **Order_Service**: The backend service module at `backend/src/services/order.service.ts` responsible for order lifecycle management.
- **Rider_Service**: The backend service module at `backend/src/services/rider.service.ts` responsible for rider location tracking and dispatch.
- **Auth_Service**: The backend service module at `backend/src/services/auth.service.ts` responsible for registration, login, and token management.
- **Refund_Service**: The backend service module at `backend/src/services/refund.service.ts` responsible for initiating Chapa payment refunds.
- **Dispatch_Session**: An in-memory record tracking which riders have been contacted for a given order, held in the `dispatchSessions` Map.
- **Retry_Session**: An in-memory record tracking no-rider retry state for a given order, held in the `retrySessionsNoRider` Map.
- **rider_locations**: The PostgreSQL table storing rider GPS coordinates and availability status.
- **rider_profiles**: The PostgreSQL table storing rider vehicle and license information, created in migration `004_inconsistencies_fix.sql`.
- **refresh_tokens**: The PostgreSQL table storing hashed refresh tokens with expiry timestamps.
- **Chapa**: The third-party payment gateway used for payment processing and refunds.
- **Supabase**: The managed PostgreSQL hosting provider used for the platform database.
- **Render**: The cloud hosting provider used for the backend; instances spin down on inactivity causing process restarts.
- **minimum_order_value**: A per-restaurant threshold (stored in the `restaurants` table) below which orders must be rejected.
- **cancelled_by**: A column on the `orders` table recording which actor (`customer`, `restaurant`, or `admin`) initiated a cancellation.
- **payment_status**: A column on the `orders` table reflecting the current state of the payment (`paid`, `refunded`, `refund_failed`, etc.).
- **email_verified**: A boolean column on the `users` table indicating whether the user has completed OTP email verification.

---

## Requirements

### Requirement 1: Rider Location UPSERT (Bug 1)

**User Story:** As a platform operator, I want rider location updates to overwrite the rider's existing record rather than insert new rows, so that the `rider_locations` table does not grow unbounded and query performance is maintained.

#### Acceptance Criteria

1. WHEN `updateRiderLocation` is called for a rider, THE Rider_Service SHALL upsert the rider's location row using `ON CONFLICT (rider_id) DO UPDATE` so that exactly one row per rider exists in `rider_locations` after the operation.
2. WHEN `updateRiderLocation` is called N times for the same rider, THE Rider_Service SHALL result in exactly one row for that rider in `rider_locations`, regardless of N.
3. WHEN `setRiderAvailability` is called for a rider, THE Rider_Service SHALL upsert the rider's availability using the same single-row-per-rider constraint.
4. THE `rider_locations` table SHALL have a `UNIQUE` constraint on `rider_id` to enforce the single-row invariant at the database level.
5. WHEN `findNearbyRiders` queries `rider_locations`, THE Rider_Service SHALL retrieve the single current row per rider without requiring `DISTINCT ON` or `ORDER BY timestamp DESC LIMIT 1` sub-queries.

**Correctness Properties:**

- **Idempotence**: FOR ALL valid (riderId, latitude, longitude, availability) inputs, calling `updateRiderLocation` once and calling it twice with the same arguments SHALL produce identical `rider_locations` table state (one row, same values).
- **Invariant**: FOR ALL sequences of N ≥ 1 calls to `updateRiderLocation` for the same riderId, the count of rows in `rider_locations` WHERE `rider_id = riderId` SHALL equal 1.
- **Last-write-wins**: FOR ALL pairs of sequential calls (call1, call2) to `updateRiderLocation` for the same riderId, the row in `rider_locations` SHALL reflect the values from call2.

---

### Requirement 2: Persistent Dispatch State (Bug 2)

**User Story:** As a platform operator, I want active dispatch and retry sessions to survive server restarts, so that orders are not silently stuck at `ready_for_pickup` when Render spins down the backend process.

#### Acceptance Criteria

1. THE Rider_Service SHALL persist Dispatch_Session state to the database when a dispatch is started, so that the session can be recovered after a process restart.
2. THE Rider_Service SHALL persist Retry_Session state to the database when a no-rider retry is scheduled, so that the retry schedule can be recovered after a process restart.
3. WHEN the backend process starts, THE Rider_Service SHALL query the database for any orders in `ready_for_pickup` status that have an active persisted dispatch session and resume dispatch for those orders.
4. WHEN a Dispatch_Session or Retry_Session is cancelled or completed, THE Rider_Service SHALL delete the corresponding persisted record from the database.
5. WHEN the backend process starts, THE Order_Service SHALL query for orders in `ready_for_pickup` status with no active dispatch session older than `DISPATCH_MAX_DURATION_MINUTES` and cancel those orders with reason `'No rider available'`.
6. IF a persisted dispatch session references an order that is no longer in `ready_for_pickup` status, THEN THE Rider_Service SHALL discard that session without resuming dispatch.

---

### Requirement 3: Dispatch Loop Termination (Bug 3)

**User Story:** As a rider, I want the dispatch system to stop contacting me after I decline an order, so that I am not spammed with repeated delivery requests for the same order.

#### Acceptance Criteria

1. WHEN `riderDeclined` is called and `riderIndex` reaches or exceeds the length of the `riders` array in the Dispatch_Session, THE Rider_Service SHALL NOT reset `riderIndex` to 0 and re-contact the same riders.
2. WHEN all riders in a Dispatch_Session have declined, THE Rider_Service SHALL transition the Dispatch_Session to a no-rider retry state and schedule a retry via `scheduleRetry`, rather than looping back to the first rider.
3. WHEN the elapsed time since dispatch start exceeds `DISPATCH_MAX_DURATION_MINUTES`, THE Rider_Service SHALL terminate the Dispatch_Session and invoke `cancelOrderNoRider`.
4. FOR ALL Dispatch_Sessions with N riders, each rider SHALL receive at most one delivery request notification per dispatch cycle before the session either finds an acceptor or exhausts all riders.
5. WHEN a Dispatch_Session exhausts all riders without acceptance, THE Rider_Service SHALL emit a `searching_rider` socket event to the customer and restaurant owner before scheduling the next retry.

**Correctness Properties:**

- **Termination**: FOR ALL Dispatch_Sessions with a finite list of N riders, the dispatch loop SHALL terminate (either by acceptance, exhaustion, or timeout) within a bounded number of steps proportional to N × `RIDER_TIMEOUT_SECONDS` plus `DISPATCH_MAX_DURATION_MINUTES`.
- **No duplicate notifications**: FOR ALL riders in a single dispatch cycle, the count of `delivery_request` events emitted to a given riderId SHALL equal 1 per cycle.

---

### Requirement 4: Minimum Order Value Enforcement (Bug 4)

**User Story:** As a restaurant owner, I want orders below my configured minimum order value to be rejected at order creation time, so that I do not receive unprofitable orders.

#### Acceptance Criteria

1. WHEN `createOrder` is called, THE Order_Service SHALL fetch the `minimum_order_value` for the target restaurant from the `restaurants` table.
2. IF the computed `subtotal` of the order is less than the restaurant's `minimum_order_value`, THEN THE Order_Service SHALL reject the order with HTTP status 422 and an error message indicating the minimum order value.
3. WHEN a restaurant's `minimum_order_value` is 0 or NULL, THE Order_Service SHALL treat the minimum as 0 and allow any non-zero order.
4. THE minimum order value check SHALL be performed before any payment initialization with Chapa, so that no payment reference is created for a rejected order.
5. WHEN `minimum_order_value` is enforced, THE Order_Service SHALL include the restaurant's `minimum_order_value` in the error response body so the client can display it to the customer.

**Correctness Properties:**

- **Boundary**: FOR ALL orders where `subtotal == minimum_order_value`, THE Order_Service SHALL accept the order (boundary is inclusive).
- **Rejection below boundary**: FOR ALL orders where `subtotal < minimum_order_value` and `minimum_order_value > 0`, THE Order_Service SHALL reject the order with status 422.
- **Metamorphic**: FOR ALL restaurants R with `minimum_order_value` M, an order with subtotal M − 0.01 SHALL be rejected and an order with subtotal M SHALL be accepted.

---

### Requirement 5: Cancelled-By Attribution for No-Rider Cancellations (Bug 5)

**User Story:** As a platform operator, I want auto-cancellations due to no available rider to record `cancelled_by = 'system'` in the orders table, so that cancellation audits can distinguish system-initiated cancellations from customer or restaurant cancellations.

#### Acceptance Criteria

1. WHEN `cancelOrderNoRider` is called, THE Order_Service SHALL set `cancelled_by` to `'system'` on the cancelled order record.
2. WHEN `cancelOrderNoRider` is called, THE Order_Service SHALL set `cancelled_at` to the current timestamp on the cancelled order record.
3. WHEN `cancelOrderNoRider` is called, THE Order_Service SHALL set `cancellation_reason` to `'No rider available'` on the cancelled order record.
4. THE `cancelled_by` column constraint in the database SHALL be extended to include `'system'` as a valid value alongside `'customer'`, `'restaurant'`, and `'admin'`.
5. WHEN an order is cancelled by `cancelOrderNoRider`, a subsequent query for that order SHALL return `cancelled_by = 'system'`, `cancelled_at` as a non-NULL timestamp, and `cancellation_reason = 'No rider available'`.

**Correctness Properties:**

- **Invariant**: FOR ALL orders cancelled via `cancelOrderNoRider`, the resulting order row SHALL satisfy: `cancelled_by IS NOT NULL AND cancelled_at IS NOT NULL AND cancellation_reason IS NOT NULL`.

---

### Requirement 6: Email Verification Enforcement at Login (Bug 8)

**User Story:** As a platform security officer, I want users who have not verified their email address to be blocked from logging in, so that unverified accounts cannot access the platform.

#### Acceptance Criteria

1. WHEN `login` is called with valid credentials for a user whose `email_verified` is FALSE, THE Auth_Service SHALL reject the login with HTTP status 403 and an error message instructing the user to verify their email.
2. WHEN `login` is called with valid credentials for a user whose `email_verified` is TRUE, THE Auth_Service SHALL issue a JWT and refresh token as normal.
3. WHEN `login` is called with invalid credentials, THE Auth_Service SHALL return HTTP status 401 regardless of `email_verified` status, to avoid leaking account existence.
4. THE email verification check SHALL be performed after password validation, so that the error response for an unverified account is only returned when the password is correct.
5. WHEN a user is blocked at login due to unverified email, THE Auth_Service SHALL NOT insert a new refresh token row into the `refresh_tokens` table.

**Correctness Properties:**

- **Security invariant**: FOR ALL users where `email_verified = FALSE`, no call to `login` with any password SHALL result in a JWT being issued.
- **Round-trip**: A user who registers, verifies their OTP, then calls `login` SHALL receive a valid JWT. A user who registers but does not verify SHALL NOT receive a JWT on `login`.

---

### Requirement 7: Refund Failure Observability (Bug 10)

**User Story:** As a platform operator, I want failed refund attempts to be recorded on the order record, so that support staff can identify orders requiring manual refund intervention.

#### Acceptance Criteria

1. WHEN `initiateRefund` throws after exhausting all retries, THE Refund_Service SHALL update the order's `payment_status` to `'refund_failed'` in the database before propagating or swallowing the error.
2. WHEN `initiateRefund` succeeds, THE Refund_Service SHALL update the order's `payment_status` to `'refunded'` in the database.
3. WHEN `cancelOrderNoRider` calls `initiateRefund`, THE Order_Service SHALL await the result and handle the failure case by setting `payment_status = 'refund_failed'` on the order, rather than using `void`.
4. WHEN `rejectOrder` calls `initiateRefund`, THE Order_Service SHALL await the result and handle the failure case by setting `payment_status = 'refund_failed'` on the order, rather than using `void`.
5. WHEN an order's `payment_status` is `'refund_failed'`, THE Order_Service SHALL expose this status in the order detail response so that admin tooling can surface it.
6. IF `initiateRefund` receives a 4xx response from Chapa, THEN THE Refund_Service SHALL set `payment_status` to `'refund_failed'` and SHALL NOT retry.

**Correctness Properties:**

- **State completeness**: FOR ALL orders that have been cancelled (status = `'cancelled'`) with a non-NULL `payment_reference`, the `payment_status` SHALL be one of `'refunded'` or `'refund_failed'` — never NULL or `'paid'` — after the cancellation flow completes.
- **Idempotence of status update**: Calling `initiateRefund` for an order that already has `payment_status = 'refunded'` SHALL be a no-op and SHALL NOT change the status.

---

### Requirement 8: Refresh Token Cleanup (Bug 13)

**User Story:** As a platform operator, I want old and expired refresh tokens to be removed from the database, so that the `refresh_tokens` table does not grow unbounded and stale tokens cannot be used.

#### Acceptance Criteria

1. WHEN `login` is called successfully, THE Auth_Service SHALL delete all existing refresh tokens for that user from the `refresh_tokens` table before inserting the new token.
2. WHEN `verifyOtp` issues tokens after successful verification, THE Auth_Service SHALL delete all existing refresh tokens for that user before inserting the new token.
3. THE Auth_Service SHALL provide a scheduled cleanup function that deletes all rows from `refresh_tokens` where `expires_at < NOW()`.
4. WHEN the scheduled cleanup runs, THE Auth_Service SHALL delete expired tokens for all users, not only the currently authenticating user.
5. AFTER `login` completes successfully for a given userId, the count of rows in `refresh_tokens` WHERE `user_id = userId` SHALL equal exactly 1.

**Correctness Properties:**

- **Invariant after login**: FOR ALL users, after a successful `login` call, the count of rows in `refresh_tokens` for that user SHALL equal 1.
- **Idempotence of cleanup**: Running the expired-token cleanup function twice in succession SHALL produce the same `refresh_tokens` table state as running it once.
- **Metamorphic**: FOR ALL users who call `login` N times, the count of rows in `refresh_tokens` for that user SHALL equal 1 regardless of N.

---

### Requirement 9: rider_profiles Migration Completeness (Bug 16)

**User Story:** As a backend developer, I want the `rider_profiles` table to be reliably created by the migration scripts, so that `GET /riders/profile` and `PUT /riders/profile` do not fail with a "relation does not exist" error on a fresh database.

#### Acceptance Criteria

1. THE migration `004_inconsistencies_fix.sql` SHALL contain a `CREATE TABLE IF NOT EXISTS rider_profiles` statement that creates the table with columns: `id`, `rider_id`, `license_number`, `vehicle_type`, `vehicle_plate`, `document_url`, `verified`, `created_at`, `updated_at`.
2. THE `rider_profiles` table SHALL have a `UNIQUE` constraint on `rider_id` to support the `ON CONFLICT (rider_id) DO UPDATE` upsert used in `PUT /riders/profile`.
3. WHEN migrations are run in order from `001` to the latest, THE database SHALL contain the `rider_profiles` table before any route handler that references it is invoked.
4. WHEN `GET /riders/profile` is called by an authenticated rider on a freshly migrated database, THE system SHALL return HTTP 200 with an empty object `{}` rather than a 500 error.
5. WHEN `PUT /riders/profile` is called by an authenticated rider on a freshly migrated database, THE system SHALL successfully upsert the rider's profile and return HTTP 200.
6. THE migration file SHALL be idempotent: running `004_inconsistencies_fix.sql` twice on the same database SHALL NOT produce an error.

**Correctness Properties:**

- **Round-trip**: FOR ALL valid rider profile inputs (license_number, vehicle_type, vehicle_plate, document_url), a `PUT /riders/profile` followed by `GET /riders/profile` SHALL return the same field values that were submitted.
- **Idempotence of upsert**: FOR ALL rider profile inputs, calling `PUT /riders/profile` twice with the same body SHALL produce the same stored profile as calling it once.
