# Implementation Plan

- [x] 1. Write bug condition exploration tests
  - **Property 1: Bug Condition** - Project Inconsistencies (Bugs 1, 2, 4, 5, 9, 10, 11, 12, 13)
  - **CRITICAL**: These tests MUST FAIL on unfixed code — failure confirms the bugs exist
  - **DO NOT attempt to fix the tests or the code when they fail**
  - **GOAL**: Surface counterexamples that demonstrate each bug exists
  - Write tests in `backend/src/tests/` (e.g. `inconsistencies.bug.test.ts`)
  - **Bug 1 — Description validation**: POST create-menu-item without `description` → assert HTTP 201 (will get 422 on unfixed code)
  - **Bug 2 — Missing env vars**: Import `env`, assert `env.CHAPA_PUBLIC_KEY`, `env.USE_CLOUDINARY`, `env.CHAPA_BASE_URL` are defined (will be undefined on unfixed code)
  - **Bug 4 — Broken re-dispatch**: Call `riderDeclined(orderId)` on a session with 2 riders, spy on `emitDeliveryRequest`, assert it is called for rider 2 (will not be called on unfixed code)
  - **Bug 5 — Open CORS**: Send request with `Origin: https://evil.example.com`, assert no `Access-Control-Allow-Origin` header (will be `*` on unfixed code)
  - **Bug 9 — No rate limiting**: Send 11 rapid requests to `/api/v1/auth/login`, assert 11th returns 429 (will return 200 on unfixed code)
  - **Bug 10 — No request logger**: Make any request, assert logger was called with method/path/status/ms (will not be called on unfixed code)
  - **Bug 11 — No retry**: Mock axios to fail twice then succeed, assert `initiateRefund` resolves (will reject on unfixed code)
  - **Bug 12 — Missed events lost**: Emit `order:status_changed` to an offline user, reconnect, assert event is received (will be lost on unfixed code)
  - **Bug 13 — Room leak**: Connect socket, disconnect, assert `user:<id>` room is empty (will persist on unfixed code)
  - Run all tests on UNFIXED code
  - **EXPECTED OUTCOME**: All tests FAIL (this is correct — it proves the bugs exist)
  - Document counterexamples found (e.g. "POST /menu without description → 422", "env.CHAPA_BASE_URL → undefined", "riderDeclined → emitDeliveryRequest never called")
  - Mark task complete when tests are written, run, and failures are documented
  - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.9, 1.10, 1.11, 1.12, 1.13_

- [x] 2. Write preservation property tests (BEFORE implementing fix)
  - **Property 2: Preservation** - Existing Behavior Baseline
  - **IMPORTANT**: Follow observation-first methodology — run UNFIXED code with non-buggy inputs, observe outputs, then encode as tests
  - Write tests in `backend/src/tests/` (e.g. `inconsistencies.preservation.test.ts`)
  - **Preservation 3.1**: Generate random non-empty description strings → assert create-menu-item returns 201 with description stored (observe on unfixed code first)
  - **Preservation 3.2**: Assert all pre-existing `env` keys (`CHAPA_SECRET_KEY`, `CLOUDINARY_*`, `FIREBASE_*`, rider/dispatch constants) remain defined with correct types
  - **Preservation 3.3**: Call `riderAccepted(orderId)` after creating a session → assert session is deleted and timeout is cleared
  - **Preservation 3.4**: Verify natural dispatch timeout still advances to next rider via `setTimeout` path
  - **Preservation 3.5**: Send requests from allowed origins → assert CORS permits them including preflight OPTIONS
  - **Preservation 3.6**: Construct Order objects → assert all 16 pre-existing fields (`id`, `customer_id`, `restaurant_id`, `rider_id`, `delivery_address_id`, `status`, `subtotal`, `delivery_fee`, `total`, `payment_reference`, `payment_status`, `cancellation_reason`, `cancelled_at`, `estimated_prep_time_minutes`, `created_at`, `updated_at`) are present and typed correctly
  - **Preservation 3.7**: Construct Restaurant objects → assert all 14 pre-existing fields are present and typed correctly
  - **Preservation 3.8**: Call `PUT /riders/location` and `PUT /riders/availability` → assert they return 200
  - **Preservation 3.9**: Mock axios to succeed immediately → assert `initiateRefund` makes a single call and resolves (no retry overhead)
  - **Preservation 3.10**: Emit events to connected users → assert immediate delivery (no queuing)
  - Verify all tests PASS on UNFIXED code before proceeding
  - **EXPECTED OUTCOME**: All tests PASS (this confirms baseline behavior to preserve)
  - Mark task complete when tests are written, run, and passing on unfixed code
  - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8, 3.9, 3.10_

- [x] 3. Run database migration

  - [x] 3.1 Create migration file `database/migrations/004_inconsistencies_fix.sql`
    - Add `notes TEXT`, `estimated_delivery_time TIMESTAMP`, `payment_method VARCHAR(50)` columns to `orders` table using `ADD COLUMN IF NOT EXISTS`
    - Add `is_open BOOLEAN DEFAULT TRUE`, `operating_hours JSONB`, `minimum_order_value DECIMAL(10,2) DEFAULT 0` columns to `restaurants` table using `ADD COLUMN IF NOT EXISTS`
    - Create `rider_profiles` table with `id`, `rider_id` (FK → users), `license_number`, `vehicle_type`, `vehicle_plate`, `document_url`, `verified`, `created_at`, `updated_at`, `UNIQUE(rider_id)`
    - _Bug_Condition: isBugCondition_6 (missing Order fields), isBugCondition_7 (missing Restaurant fields), isBugCondition_8 (no rider_profiles table)_
    - _Preservation: Existing columns are untouched; IF NOT EXISTS guards prevent re-run errors_
    - _Requirements: 2.6, 2.7, 2.8_

  - [x] 3.2 Apply the migration to the database
    - Run `004_inconsistencies_fix.sql` against the target database (Supabase SQL editor or psql)
    - Verify new columns exist in `orders` and `restaurants`
    - Verify `rider_profiles` table was created
    - _Requirements: 2.6, 2.7, 2.8_

- [x] 4. Install required packages

  - [x] 4.1 Install runtime and dev dependencies
    - Run `npm install axios express-rate-limit` in `backend/`
    - Run `npm install --save-dev @types/express-rate-limit` in `backend/`
    - Verify `axios` and `express-rate-limit` appear in `package.json` dependencies
    - _Requirements: 2.3, 2.9, 2.11_

- [x] 5. Fix environment configuration

  - [x] 5.1 Add missing env vars to `backend/src/config/env.ts`
    - Add `CHAPA_PUBLIC_KEY: process.env.CHAPA_PUBLIC_KEY || ''`
    - Add `USE_CLOUDINARY: process.env.USE_CLOUDINARY === 'true'`
    - Add `CHAPA_BASE_URL: process.env.CHAPA_BASE_URL || 'https://api.chapa.co/v1'`
    - Add `ALLOWED_ORIGINS: process.env.ALLOWED_ORIGINS || 'http://localhost:3000,http://localhost:3001'`
    - Do NOT remove or rename any existing keys
    - _Bug_Condition: isBugCondition_2 — CHAPA_PUBLIC_KEY, USE_CLOUDINARY, CHAPA_BASE_URL undefined_
    - _Expected_Behavior: env.CHAPA_PUBLIC_KEY (string), env.USE_CLOUDINARY (boolean), env.CHAPA_BASE_URL (string), env.ALLOWED_ORIGINS (string) all defined_
    - _Preservation: All pre-existing keys (CHAPA_SECRET_KEY, CLOUDINARY_*, FIREBASE_*, rider/dispatch constants) remain unchanged_
    - _Requirements: 2.2, 3.2_

- [x] 6. Fix description validation in menu controller

  - [x] 6.1 Make `description` optional in `backend/src/controllers/menu.controller.ts`
    - Change `body('description').notEmpty().trim()` → `body('description').optional().trim()` in `createMenuItemValidation`
    - No other changes to the file
    - _Bug_Condition: isBugCondition_1 — request without description field rejected with 422_
    - _Expected_Behavior: POST create-menu-item without description returns HTTP 201 with description: null_
    - _Preservation: Requests with a valid description string continue to return 201 with description stored_
    - _Requirements: 2.1, 3.1_

- [x] 7. Fix refund service — env URL and retry logic

  - [x] 7.1 Refactor `backend/src/services/refund.service.ts`
    - Replace `import https from 'https'` with `import axios from 'axios'`
    - Import `env` from `../config/env`
    - Derive base URL from `env.CHAPA_BASE_URL` instead of hardcoding `api.chapa.co`
    - Wrap the axios POST in a retry loop: up to 3 attempts, exponential backoff (100 ms → 200 ms → 400 ms), retry only on network errors or 5xx responses (not 4xx)
    - _Bug_Condition: isBugCondition_3 (hardcoded hostname), isBugCondition_11 (no retry on transient error)_
    - _Expected_Behavior: URL derived from env.CHAPA_BASE_URL; transient failures retried up to 3 times_
    - _Preservation: Refund that succeeds on first attempt behaves identically (single call, log, resolve)_
    - _Requirements: 2.3, 2.11, 3.9_

- [-] 8. Fix rider re-dispatch logic

  - [x] 8.1 Extend `dispatchSessions` and fix `riderDeclined` in `backend/src/services/rider.service.ts`
    - Extend the `dispatchSessions` map value type to include `restaurant: { name: string; address: string }`, `customerAddress: string`, `deliveryFee: number`
    - In `startDispatch`, store those three values when creating the session entry
    - In `riderDeclined`, after incrementing `session.riderIndex`, call `sendToNextRider(orderId, session.restaurant, session.customerAddress, session.deliveryFee)` directly
    - Remove the stale comment about re-querying
    - _Bug_Condition: isBugCondition_4 — riderDeclined increments index but never calls sendToNextRider, dispatch stalls_
    - _Expected_Behavior: riderDeclined calls sendToNextRider so next rider receives delivery request immediately_
    - _Preservation: riderAccepted continues to clear session and cancel timeout; natural timeout path unchanged_
    - _Requirements: 2.4, 3.3, 3.4_

- [-] 9. Add rate limiter middleware

  - [x] 9.1 Create `backend/src/middleware/rateLimiter.ts`
    - Export `rateLimiter`: `rateLimit({ windowMs: 15 * 60 * 1000, max: 100 })` for global use
    - Export `authRateLimiter`: `rateLimit({ windowMs: 15 * 60 * 1000, max: 10 })` for auth endpoints
    - _Bug_Condition: isBugCondition_9 — no rate limiting, all requests pass regardless of volume_
    - _Expected_Behavior: requests exceeding threshold return HTTP 429_
    - _Requirements: 2.9_

- [x] 10. Add request logger middleware

  - [x] 10.1 Create `backend/src/middleware/requestLogger.ts`
    - Record `start = Date.now()` on the way in
    - Hook `res.on('finish', ...)` to log `method`, `path`, `statusCode`, and `Date.now() - start` ms using the existing `logger` utility
    - _Bug_Condition: isBugCondition_10 — no request logging middleware applied_
    - _Expected_Behavior: every request emits a log line with method, path, status, elapsed ms_
    - _Requirements: 2.10_

- [x] 11. Configure CORS, rate limiting, and request logging in app.ts

  - [x] 11.1 Update `backend/src/app.ts`
    - Import `env` from `./config/env`
    - Replace `app.use(cors())` with a configured cors call: split `env.ALLOWED_ORIGINS` on `,` and pass the array as the `origin` whitelist
    - Import `rateLimiter` and `authRateLimiter` from `./middleware/rateLimiter`
    - Import `requestLogger` from `./middleware/requestLogger`
    - Apply `app.use(rateLimiter)` globally (after `requestIdMiddleware`)
    - Apply `app.use('/api/v1/auth', authRateLimiter)` before the main router
    - Apply `app.use(requestLogger)` after `requestIdMiddleware`
    - _Bug_Condition: isBugCondition_5 (open CORS), isBugCondition_9 (no rate limiter), isBugCondition_10 (no request logger)_
    - _Expected_Behavior: CORS restricted to ALLOWED_ORIGINS; 429 on threshold breach; log line per request_
    - _Preservation: Allowed origins continue to pass CORS including preflight OPTIONS_
    - _Requirements: 2.5, 2.9, 2.10, 3.5_

- [x] 12. Update TypeScript models

  - [x] 12.1 Add new fields to `backend/src/models/order.model.ts`
    - Add to `Order` interface: `notes?: string | null`, `estimated_delivery_time?: Date | null`, `payment_method?: string | null`
    - Do NOT remove or rename any existing fields
    - _Bug_Condition: isBugCondition_6 — notes, estimated_delivery_time, payment_method absent from Order_
    - _Preservation: All 16 pre-existing Order fields remain present with identical names and types_
    - _Requirements: 2.6, 3.6_

  - [x] 12.2 Add new fields to `backend/src/models/restaurant.model.ts`
    - Add to `Restaurant` interface: `is_open?: boolean`, `operating_hours?: Record<string, { open: string; close: string }> | null`, `minimum_order_value?: number`
    - Do NOT remove or rename any existing fields
    - _Bug_Condition: isBugCondition_7 — is_open, operating_hours, minimum_order_value absent from Restaurant_
    - _Preservation: All 14 pre-existing Restaurant fields remain present with identical names and types_
    - _Requirements: 2.7, 3.7_

- [x] 13. Add rider profile endpoints

  - [x] 13.1 Add `GET /riders/profile` and `PUT /riders/profile` to `backend/src/routes/riders.ts`
    - `GET /riders/profile`: authenticate + authorize('rider'), query `rider_profiles` by `rider_id = req.userId`, return profile data (or empty object if not yet created)
    - `PUT /riders/profile`: authenticate + authorize('rider'), validate body (`license_number`, `vehicle_type`, `vehicle_plate`, `document_url` — all optional strings), upsert into `rider_profiles` using `ON CONFLICT (rider_id) DO UPDATE`, return updated record
    - Do NOT modify existing `/location`, `/availability`, or `/available` routes
    - _Bug_Condition: isBugCondition_8 — GET/PUT /riders/profile returns 404_
    - _Expected_Behavior: GET returns rider profile data; PUT upserts and returns updated record_
    - _Preservation: Existing rider endpoints continue to function without change_
    - _Requirements: 2.8, 3.8_

- [x] 14. Fix socket service — room cleanup and missed event queue

  - [x] 14.1 Update `backend/src/services/socket.service.ts`
    - In the `disconnect` handler, call `socket.leave('user:' + userId)` to release the room
    - Add module-level `missedEventQueue: Map<string, Array<{ event: string; payload: unknown; ts: number }>>` 
    - Add `queueEvent(userId, event, payload)` helper: push to queue, schedule TTL cleanup (default 5 minutes) to remove stale entries
    - Add `flushQueue(socket, userId)` helper: replay queued events in order, then clear the queue for that user
    - In the `connection` handler, call `flushQueue(socket, userId)` after joining the `user:<id>` room
    - In all `emit*` functions, check if `io.sockets.adapter.rooms.get('user:' + targetUserId)` is empty/undefined; if so, call `queueEvent` instead of emitting directly
    - _Bug_Condition: isBugCondition_12 (missed events lost on disconnect), isBugCondition_13 (room not cleaned up on disconnect)_
    - _Expected_Behavior: events emitted while user is offline are queued and flushed on reconnect within TTL; room is left on disconnect_
    - _Preservation: events to connected users are delivered immediately without queuing_
    - _Requirements: 2.12, 2.13, 3.10_

- [x] 15. Verify bug condition exploration tests now pass

  - [x] 15.1 Re-run exploration tests from task 1
    - **Property 1: Expected Behavior** - All Bug Conditions Fixed
    - **IMPORTANT**: Re-run the SAME tests from task 1 — do NOT write new tests
    - Run `backend/src/tests/inconsistencies.bug.test.ts` (or equivalent)
    - **EXPECTED OUTCOME**: All tests PASS (confirms all 13 bugs are fixed)
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9, 2.10, 2.11, 2.12, 2.13_

  - [x] 15.2 Verify preservation tests still pass
    - **Property 2: Preservation** - No Regressions
    - **IMPORTANT**: Re-run the SAME tests from task 2 — do NOT write new tests
    - Run `backend/src/tests/inconsistencies.preservation.test.ts` (or equivalent)
    - **EXPECTED OUTCOME**: All tests PASS (confirms no regressions)
    - _Requirements: 3.1, 3.2, 3.3, 3.4, 3.5, 3.6, 3.7, 3.8, 3.9, 3.10_

- [x] 16. Checkpoint — Ensure all tests pass
  - Run the full test suite: `cd backend && npx jest --run` (or `npm test`)
  - Ensure all pre-existing tests continue to pass
  - Ensure all new exploration and preservation tests pass
  - Ask the user if any questions arise
