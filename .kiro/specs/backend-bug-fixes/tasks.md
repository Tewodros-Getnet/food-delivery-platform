# Implementation Plan: Backend Bug Fixes

## Overview

Nine confirmed backend bugs are fixed in a single surgical pass across the service layer and database schema. All changes are confined to `rider.service.ts`, `order.service.ts`, `auth.service.ts`, `refund.service.ts`, `scheduler.service.ts`, and a new migration file. No controller or route changes are required except where a new HTTP status code must be returned.

## Tasks

- [x] 1. Write migration 005_bug_fixes.sql for all schema changes
  - Create `database/migrations/005_bug_fixes.sql`
  - Add `UNIQUE` constraint on `rider_locations.rider_id` (deduplicate existing rows first)
  - Create `dispatch_sessions` table with columns: `order_id`, `rider_index`, `riders` (JSONB), `restaurant` (JSONB), `customer_address`, `delivery_fee`, `start_time`, `created_at`
  - Create `retry_sessions_no_rider` table with columns: `order_id`, `retry_count`, `restaurant_id`, `customer_id`, `restaurant_owner_id`, `created_at`
  - Extend `orders.cancelled_by` CHECK constraint to include `'system'`
  - Ensure all DDL statements use `IF NOT EXISTS` / `DROP CONSTRAINT IF EXISTS` for idempotency
  - _Requirements: 1.4, 2.1, 2.2, 5.4_

- [x] 2. Fix Bug 1 — Rider Location UPSERT in rider.service.ts
  - [x] 2.1 Replace INSERT with UPSERT in `updateRiderLocation`
    - Change the INSERT query to `INSERT ... ON CONFLICT (rider_id) DO UPDATE SET latitude, longitude, availability, timestamp = NOW()`
    - _Requirements: 1.1, 1.2_

  - [x] 2.2 Replace INSERT with UPSERT in `setRiderAvailability`
    - Replace the two-step INSERT logic with a single `INSERT ... ON CONFLICT (rider_id) DO UPDATE SET availability, timestamp = NOW()` using `(0, 0)` as the placeholder coordinates
    - _Requirements: 1.3_

  - [x] 2.3 Simplify `findNearbyRiders` to use single-row query
    - Remove `DISTINCT ON (rider_id)` and `ORDER BY rider_id, timestamp DESC` from both query branches now that each rider has exactly one row
    - _Requirements: 1.5_

  - [ ]* 2.4 Write property test for rider location upsert idempotence
    - **Property 1: Rider location upsert idempotence**
    - Use fast-check to generate arbitrary `(riderId, lat, lon, availability)` tuples; call `updateRiderLocation` N times and assert exactly one row exists with the last-written values
    - Tag comment: `// Feature: backend-bug-fixes, Property 1: Rider location upsert idempotence`
    - **Validates: Requirements 1.1, 1.2, 1.3**

  - [ ]* 2.5 Write unit tests for Bug 1
    - Mock DB, call `updateRiderLocation` twice for the same rider, assert `ON CONFLICT` SQL is used and row count equals 1
    - Test `setRiderAvailability` with no prior location row (placeholder path) and with an existing row
    - _Requirements: 1.1, 1.2, 1.3_

- [x] 3. Fix Bug 2 — Persistent Dispatch State in rider.service.ts
  - [x] 3.1 Add DB persistence helpers for dispatch sessions
    - Implement `persistUpsertDispatchSession(orderId, session)` using `INSERT ... ON CONFLICT (order_id) DO UPDATE`
    - Implement `persistDeleteDispatchSession(orderId)` using `DELETE FROM dispatch_sessions WHERE order_id = $1`
    - _Requirements: 2.1, 2.4_

  - [x] 3.2 Add DB persistence helpers for retry sessions
    - Implement `persistUpsertRetrySession(orderId, session)` using `INSERT ... ON CONFLICT (order_id) DO UPDATE`
    - Implement `persistDeleteRetrySession(orderId)` using `DELETE FROM retry_sessions_no_rider WHERE order_id = $1`
    - _Requirements: 2.2, 2.4_

  - [x] 3.3 Wire persistence calls into all Map mutation sites
    - In `startDispatch`: call `persistUpsertDispatchSession` after `dispatchSessions.set`
    - In `scheduleRetry` (no-rider path): call `persistUpsertRetrySession` after `retrySessionsNoRider.set`
    - In `riderAccepted`: call `persistDeleteDispatchSession` and `persistDeleteRetrySession` after Map deletes
    - In `cancelRetrySession`: call `persistDeleteRetrySession` after Map delete
    - In `sendToNextRider` (rider exhausted path): call `persistDeleteDispatchSession` after Map delete
    - _Requirements: 2.1, 2.2, 2.4_

  - [x] 3.4 Implement `recoverDispatchSessions` startup function
    - Query `dispatch_sessions` joined with `orders` where `orders.status = 'ready_for_pickup'`
    - For sessions older than `DISPATCH_MAX_DURATION_MINUTES`, call `cancelOrderNoRider` and delete the session
    - For valid sessions, repopulate the in-memory `dispatchSessions` Map and call `sendToNextRider`
    - Query `retry_sessions_no_rider` joined with `orders` where `orders.status = 'ready_for_pickup'` and repopulate `retrySessionsNoRider` Map, calling `scheduleRetry` for each
    - Discard sessions whose order is no longer in `ready_for_pickup`
    - Export `recoverDispatchSessions` from `rider.service.ts`
    - _Requirements: 2.3, 2.5, 2.6_

  - [x] 3.5 Wire `recoverDispatchSessions` into application startup
    - In `backend/src/index.ts`, import `recoverDispatchSessions` from `rider.service`
    - Call `await recoverDispatchSessions()` after the DB pool is ready and before the HTTP server starts listening
    - _Requirements: 2.3_

  - [ ]* 3.6 Write integration test for startup recovery (Bug 2)
    - Insert a `dispatch_sessions` row directly into the test DB, call `recoverDispatchSessions()`, verify the in-memory Map is populated and `sendToNextRider` is invoked
    - _Requirements: 2.3, 2.6_

- [x] 4. Fix Bug 3 — Dispatch Loop Termination in rider.service.ts
  - [x] 4.1 Remove the `riderIndex = 0` reset in `sendToNextRider`
    - Replace the `if (session.riderIndex >= session.riders.length) { session.riderIndex = 0; }` block with the exhaustion transition: delete the dispatch session, fetch restaurant owner, emit `searching_rider`, set retry session, call `persistUpsertRetrySession`, and call `scheduleRetry`
    - _Requirements: 3.1, 3.2, 3.5_

  - [ ]* 4.2 Write unit tests for dispatch loop termination (Bug 3)
    - Mock `emitDeliveryRequest` and `scheduleRetry`; create a session with 2 riders; call `riderDeclined` twice; assert `scheduleRetry` is called exactly once and no third `emitDeliveryRequest` is emitted
    - _Requirements: 3.1, 3.2, 3.4_

- [x] 5. Checkpoint — Ensure all rider.service.ts tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 6. Fix Bug 4 — Minimum Order Value Enforcement in order.service.ts
  - [x] 6.1 Extend restaurant query to fetch `minimum_order_value`
    - In `createOrder`, change the restaurant SELECT to also fetch `minimum_order_value`: `SELECT latitude, longitude, is_open, minimum_order_value FROM restaurants WHERE id = $1`
    - _Requirements: 4.1_

  - [x] 6.2 Add minimum order value check before Chapa initialisation
    - After `subtotal` is computed, read `r.minimum_order_value ?? 0`; if `subtotal < minimumOrderValue`, throw an error with `statusCode = 422` and include `minimumOrderValue` on the error object
    - Ensure no Chapa `initializePayment` call is made for rejected orders
    - _Requirements: 4.2, 4.3, 4.4, 4.5_

  - [ ]* 6.3 Write property test for minimum order value boundary (Bug 4)
    - **Property 4: Minimum order value boundary**
    - Use fast-check to generate arbitrary `(minimumOrderValue, subtotal)` pairs; assert orders with `subtotal < minimumOrderValue` are rejected with 422 and Chapa is never called; assert orders with `subtotal >= minimumOrderValue` proceed
    - Tag comment: `// Feature: backend-bug-fixes, Property 4: Minimum order value boundary`
    - **Validates: Requirements 4.2, 4.4**

  - [ ]* 6.4 Write unit tests for Bug 4
    - Mock DB to return `minimum_order_value = 100`; call `createOrder` with subtotal 99 → expect 422; subtotal 100 → expect success; assert Chapa not called on rejection
    - _Requirements: 4.2, 4.3, 4.4, 4.5_

- [x] 7. Fix Bug 5 — Cancelled-By Attribution in order.service.ts
  - [x] 7.1 Set `cancelled_by: 'system'` and remove premature `payment_status` in `cancelOrderNoRider`
    - In `cancelOrderNoRider`, pass `cancelled_by: 'system'`, `cancelled_at: new Date()`, `cancellation_reason: 'No rider available'` to `updateOrderStatus`
    - Remove `payment_status: 'refunded'` from the `updateOrderStatus` call (payment status is now managed by `refund.service.ts`)
    - _Requirements: 5.1, 5.2, 5.3_

  - [ ]* 7.2 Write unit tests for Bug 5
    - Mock DB; call `cancelOrderNoRider`; assert `updateOrderStatus` is called with `cancelled_by: 'system'`, non-null `cancelled_at`, and `cancellation_reason: 'No rider available'`; assert `payment_status: 'refunded'` is NOT passed
    - _Requirements: 5.1, 5.2, 5.3, 5.5_

- [x] 8. Fix Bug 10 — Refund Failure Observability
  - [x] 8.1 Update `payment_status` on success and failure in refund.service.ts
    - In `initiateRefund`, after a successful Chapa response, execute `UPDATE orders SET payment_status = 'refunded', updated_at = NOW() WHERE id = $1`
    - In the catch block (after all retries exhausted or on 4xx), execute `UPDATE orders SET payment_status = 'refund_failed', updated_at = NOW() WHERE id = $1` before re-throwing
    - _Requirements: 7.1, 7.2, 7.6_

  - [x] 8.2 Replace `void initiateRefund` with `await` in order.service.ts callers
    - In `cancelOrderNoRider`: replace `void initiateRefund(orderId)` with a `try { await initiateRefund(orderId); } catch { logger.error('Refund failed for order', { orderId }); }` block
    - In `rejectOrder`: apply the same `await` + catch pattern
    - _Requirements: 7.3, 7.4_

  - [ ]* 8.3 Write property test for refund status completeness (Bug 10)
    - **Property 7: Refund status completeness**
    - Use fast-check to generate order IDs; mock Chapa to randomly succeed or fail; assert `payment_status` is always `'refunded'` or `'refund_failed'` after the cancellation flow, never NULL or `'paid'`
    - Tag comment: `// Feature: backend-bug-fixes, Property 7: Refund status completeness`
    - **Validates: Requirements 7.1, 7.2**

  - [ ]* 8.4 Write unit tests for Bug 10
    - Mock Chapa to throw; call `initiateRefund`; assert `UPDATE orders SET payment_status = 'refund_failed'` is executed
    - Mock Chapa to succeed; call `initiateRefund`; assert `UPDATE orders SET payment_status = 'refunded'` is executed
    - _Requirements: 7.1, 7.2, 7.6_

- [x] 9. Fix Bug 8 — Email Verification at Login in auth.service.ts
  - [x] 9.1 Add `email_verified` check after password validation in `login`
    - In `login`, after `bcrypt.compare` succeeds, query `email_verified` from the user row (it is already fetched via `SELECT * FROM users`)
    - If `email_verified` is false, throw an error with `statusCode = 403` and message `'Please verify your email before logging in'` — do NOT insert a refresh token
    - _Requirements: 6.1, 6.4, 6.5_

  - [ ]* 9.2 Write property test for unverified users cannot obtain a JWT (Bug 8)
    - **Property 6: Unverified users cannot obtain a JWT**
    - Use fast-check to generate arbitrary email/password pairs; mock DB to return `email_verified: false`; assert no JWT is issued and no `INSERT INTO refresh_tokens` is executed for any input
    - Tag comment: `// Feature: backend-bug-fixes, Property 6: Unverified users cannot obtain a JWT`
    - **Validates: Requirements 6.1, 6.5**

  - [ ]* 9.3 Write unit tests for Bug 8
    - Mock DB to return `email_verified: false`; call `login` with correct password; assert 403 thrown and no `INSERT INTO refresh_tokens`
    - Mock DB to return `email_verified: true`; call `login`; assert JWT and refresh token are returned
    - _Requirements: 6.1, 6.2, 6.4, 6.5_

- [x] 10. Fix Bug 13 — Refresh Token Cleanup in auth.service.ts and scheduler.service.ts
  - [x] 10.1 Delete existing tokens before INSERT in `login`
    - In `login`, before the `INSERT INTO refresh_tokens` query, execute `DELETE FROM refresh_tokens WHERE user_id = $1`
    - _Requirements: 8.1, 8.5_

  - [x] 10.2 Delete existing tokens before INSERT in `verifyOtp`
    - In `verifyOtp`, before the `INSERT INTO refresh_tokens` query, execute `DELETE FROM refresh_tokens WHERE user_id = $1`
    - _Requirements: 8.2, 8.5_

  - [x] 10.3 Export `cleanupExpiredTokens` from auth.service.ts
    - Add and export `async function cleanupExpiredTokens(): Promise<void>` that executes `DELETE FROM refresh_tokens WHERE expires_at < NOW()`
    - _Requirements: 8.3, 8.4_

  - [x] 10.4 Wire `cleanupExpiredTokens` into scheduler.service.ts
    - Import `cleanupExpiredTokens` from `auth.service`
    - Add a daily cron job in `scheduler.service.ts` that calls `cleanupExpiredTokens()`
    - _Requirements: 8.3, 8.4_

  - [ ]* 10.5 Write property test for exactly one refresh token per user after authentication (Bug 13)
    - **Property 8: Exactly one refresh token per user after authentication**
    - Use fast-check to generate a user ID and a count N ≥ 1; pre-populate N refresh token rows; call `login` once; assert exactly 1 row remains in `refresh_tokens` for that user
    - Tag comment: `// Feature: backend-bug-fixes, Property 8: Exactly one refresh token per user after authentication`
    - **Validates: Requirements 8.1, 8.2, 8.5**

  - [ ]* 10.6 Write property test for expired token cleanup idempotence (Bug 13)
    - **Property 9: Expired token cleanup idempotence**
    - Use fast-check to generate a mix of expired and non-expired token rows; run `cleanupExpiredTokens` twice; assert the table state after the second run equals the state after the first run
    - Tag comment: `// Feature: backend-bug-fixes, Property 9: Expired token cleanup idempotence`
    - **Validates: Requirements 8.3, 8.4**

  - [ ]* 10.7 Write unit tests for Bug 13
    - Mock DB; pre-populate 3 refresh token rows; call `login`; assert `DELETE FROM refresh_tokens WHERE user_id = $1` is executed before INSERT; assert final count equals 1
    - _Requirements: 8.1, 8.2, 8.5_

- [x] 11. Verify Bug 16 — rider_profiles Migration Completeness
  - [x] 11.1 Audit migration 004_inconsistencies_fix.sql for rider_profiles completeness
    - Confirm `CREATE TABLE IF NOT EXISTS rider_profiles` is present with all required columns: `id`, `rider_id`, `license_number`, `vehicle_type`, `vehicle_plate`, `document_url`, `verified`, `created_at`, `updated_at`
    - Confirm `UNIQUE(rider_id)` constraint is present
    - If any column or constraint is missing, add it to `004_inconsistencies_fix.sql` using `ADD COLUMN IF NOT EXISTS` or `ADD CONSTRAINT IF NOT EXISTS`
    - _Requirements: 9.1, 9.2, 9.6_

  - [ ]* 11.2 Write integration test for migration idempotence (Bug 16)
    - Run `004_inconsistencies_fix.sql` twice against the test DB; verify no error is raised and `rider_profiles` table exists with `UNIQUE(rider_id)`
    - _Requirements: 9.6_

  - [ ]* 11.3 Write property test for rider profile round-trip (Bug 16)
    - **Property 10: Rider profile round-trip**
    - Use fast-check to generate arbitrary `(license_number, vehicle_type, vehicle_plate, document_url)` inputs; call `PUT /riders/profile` then `GET /riders/profile`; assert returned fields match submitted values
    - Tag comment: `// Feature: backend-bug-fixes, Property 10: Rider profile round-trip`
    - **Validates: Requirements 9.4, 9.5**

- [x] 12. Final checkpoint — Ensure all tests pass
  - Run the full test suite (`jest --runInBand` or equivalent)
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for a faster MVP
- Each task references specific requirements for traceability
- Property tests use **fast-check** with a minimum of 100 iterations per property
- Properties 2, 3, and 5 are covered by example-based integration tests rather than PBT (they involve socket event emission and DB FK constraints)
- The in-memory Maps in `rider.service.ts` are kept as a performance cache; the DB is the source of truth after Bug 2 is fixed
- Migration `005_bug_fixes.sql` must be applied before any service code changes are deployed
