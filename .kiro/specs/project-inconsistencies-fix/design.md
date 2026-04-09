# Project Inconsistencies Fix — Bugfix Design

## Overview

The backend has accumulated 13 distinct inconsistencies spanning validation, configuration, dispatch logic, security, data models, and infrastructure services. This design formalises each bug condition, defines the expected correct behaviour, hypothesises root causes, and plans a targeted, non-breaking fix for every issue. All changes are surgical: no existing field names, types, or endpoint contracts are altered.

---

## Glossary

- **Bug_Condition (C)**: A predicate over an input or system state that identifies when a defect manifests.
- **Property (P)**: The desired observable behaviour when the bug condition holds after the fix is applied.
- **Preservation**: Existing correct behaviour that must remain identical after the fix.
- **isBugCondition_N**: Pseudocode predicate for bug N (1–13).
- **createMenuItem / createMenuItem'**: Original / fixed menu-item creation path.
- **env / env'**: Original / fixed environment configuration object.
- **initiateRefund / initiateRefund'**: Original / fixed refund service function.
- **riderDeclined / riderDeclined'**: Original / fixed rider-declined handler.
- **dispatchSessions**: In-memory Map keyed by `orderId` holding active dispatch state.
- **sendToNextRider**: Private function that emits a delivery request to the next candidate rider.
- **ALLOWED_ORIGINS**: Comma-separated list of permitted CORS origins read from the environment.
- **USE_CLOUDINARY**: Boolean env flag controlling whether Cloudinary upload is active.
- **CHAPA_BASE_URL**: Base URL for the Chapa payment API, overridable via environment.
- **missedEventQueue**: Per-userId in-memory queue holding events emitted while the user was offline.
- **TTL**: Time-to-live for queued missed events (default 5 minutes).

---

## Bug Details

### Bug Condition

The 13 bugs share a common pattern: the implementation diverges from the declared contract (type mismatch, missing config, incomplete logic, absent middleware, or missing model fields). Each is formalised below.

**Formal Specification:**

```
FUNCTION isBugCondition_1(X)
  INPUT: X of type CreateMenuItemRequest
  OUTPUT: boolean
  RETURN X.description IS NULL OR X.description IS UNDEFINED
END FUNCTION

FUNCTION isBugCondition_2(E)
  INPUT: E of type EnvConfig
  OUTPUT: boolean
  RETURN E.CHAPA_PUBLIC_KEY IS UNDEFINED
      OR E.USE_CLOUDINARY IS UNDEFINED
      OR E.CHAPA_BASE_URL IS UNDEFINED
END FUNCTION

FUNCTION isBugCondition_3(R)
  INPUT: R of type RefundRequest
  OUTPUT: boolean
  RETURN refundService.hostname = 'api.chapa.co' (hardcoded literal)
      AND env.CHAPA_BASE_URL IS DEFINED
      AND refundService.hostname ≠ parsedHostname(env.CHAPA_BASE_URL)
END FUNCTION

FUNCTION isBugCondition_4(X)
  INPUT: X of type DispatchEvent
  OUTPUT: boolean
  RETURN X.event = 'riderDeclined'
      AND dispatchSessions.has(X.orderId)
      AND nextRiderWasContacted(X.orderId) = false
END FUNCTION

FUNCTION isBugCondition_5(R)
  INPUT: R of type HttpRequest
  OUTPUT: boolean
  RETURN R.origin IS NOT IN allowedOrigins
      AND corsConfig = unrestricted (no origin whitelist)
END FUNCTION

FUNCTION isBugCondition_6(O)
  INPUT: O of type Order
  OUTPUT: boolean
  RETURN 'notes' NOT IN Order.fields
      OR 'estimated_delivery_time' NOT IN Order.fields
      OR 'payment_method' NOT IN Order.fields
END FUNCTION

FUNCTION isBugCondition_7(R)
  INPUT: R of type Restaurant
  OUTPUT: boolean
  RETURN 'is_open' NOT IN Restaurant.fields
      OR 'operating_hours' NOT IN Restaurant.fields
      OR 'minimum_order_value' NOT IN Restaurant.fields
END FUNCTION

FUNCTION isBugCondition_8(R)
  INPUT: R of type HttpRequest
  OUTPUT: boolean
  RETURN R.path IN ['/riders/profile']
      AND R.method IN ['GET', 'PUT']
      AND routeExists(R.path) = false
END FUNCTION

FUNCTION isBugCondition_9(R)
  INPUT: R of type HttpRequest
  OUTPUT: boolean
  RETURN requestCountInWindow(R.ip, R.path, 15min) > RATE_LIMIT_THRESHOLD
      AND rateLimiterMiddleware IS NOT applied
END FUNCTION

FUNCTION isBugCondition_10(R)
  INPUT: R of type HttpRequest
  OUTPUT: boolean
  RETURN requestLoggerMiddleware IS NOT applied
END FUNCTION

FUNCTION isBugCondition_11(R)
  INPUT: R of type RefundApiCall
  OUTPUT: boolean
  RETURN R.attempt = 1
      AND R.networkError IS NOT NULL
      AND retryLogic IS NOT present
END FUNCTION

FUNCTION isBugCondition_12(E)
  INPUT: E of type SocketEvent
  OUTPUT: boolean
  RETURN E.emittedWhileUserOffline = true
      AND missedEventQueue IS NOT present
END FUNCTION

FUNCTION isBugCondition_13(S)
  INPUT: S of type SocketSession
  OUTPUT: boolean
  RETURN S.disconnected = true
      AND userRoom('user:' + S.userId) NOT cleaned up
END FUNCTION
```

### Examples

- **Bug 1**: `POST /api/v1/restaurants/:id/menu` with body `{ name: "Burger", price: 5.99, category: "mains", imageBase64: "..." }` (no `description`) → HTTP 422 validation error. Expected: HTTP 201 with `description: null`.
- **Bug 2**: `env.CHAPA_PUBLIC_KEY` is `undefined` at runtime even though `.env` contains `CHAPA_PUBLIC_KEY=...`. Expected: value is accessible as `env.CHAPA_PUBLIC_KEY`.
- **Bug 3**: Refund call always hits `api.chapa.co` even when `CHAPA_BASE_URL=https://sandbox.chapa.co/v1` is set. Expected: uses the env-configured URL.
- **Bug 4**: Rider A declines order #123 → `riderDeclined('123')` increments index to 1 but never emits to Rider B. Dispatch stalls indefinitely. Expected: Rider B receives the delivery request within milliseconds.
- **Bug 5**: `OPTIONS /api/v1/orders` from `https://evil.example.com` returns `Access-Control-Allow-Origin: *`. Expected: request is rejected (no ACAO header or 403).
- **Bug 6**: `order.notes` is `undefined` even after a customer submits special instructions. Expected: field exists and is persisted.
- **Bug 7**: `restaurant.is_open` is `undefined`; customer app cannot determine if restaurant accepts orders. Expected: field exists with a boolean value.
- **Bug 8**: `GET /api/v1/riders/profile` returns 404. Expected: returns rider profile data.
- **Bug 9**: 200 rapid login attempts from one IP all succeed (no 429). Expected: 429 after 10 attempts within 15 minutes on `/api/v1/auth`.
- **Bug 10**: No log line appears for any HTTP request. Expected: each request logs `METHOD /path → STATUS in Xms`.
- **Bug 11**: Transient DNS failure on refund call → permanent failure, no retry. Expected: up to 3 retries with exponential backoff.
- **Bug 12**: Customer disconnects for 30 seconds; order status changes during that window → event lost on reconnect. Expected: missed events delivered on reconnect within TTL window.
- **Bug 13**: User `abc` connects once, never reconnects; `user:abc` room persists in memory forever. Expected: room is left on disconnect.

---

## Expected Behavior

### Preservation Requirements

**Unchanged Behaviors:**
- `POST /menu` with a valid `description` value continues to store it correctly (Bug 1 fix must not break the happy path).
- All existing `env` keys (`CHAPA_SECRET_KEY`, `CLOUDINARY_*`, `FIREBASE_*`, rider/dispatch constants) remain accessible with identical types and defaults.
- `riderAccepted()` continues to clear the dispatch session and cancel the pending timeout.
- The natural dispatch timeout (rider does not respond) continues to advance to the next rider via the existing `setTimeout` path.
- Requests from allowed origins continue to pass CORS, including preflight OPTIONS.
- All existing `Order` fields (`id`, `customer_id`, `restaurant_id`, `rider_id`, `delivery_address_id`, `status`, `subtotal`, `delivery_fee`, `total`, `payment_reference`, `payment_status`, `cancellation_reason`, `cancelled_at`, `estimated_prep_time_minutes`, `created_at`, `updated_at`) remain present and unchanged.
- All existing `Restaurant` fields (`id`, `owner_id`, `name`, `description`, `logo_url`, `cover_image_url`, `address`, `latitude`, `longitude`, `category`, `status`, `average_rating`, `created_at`, `updated_at`) remain present and unchanged.
- Existing rider endpoints (`PUT /riders/location`, `PUT /riders/availability`, `GET /riders/available`) continue to function without change.
- A Chapa refund that succeeds on the first attempt behaves identically to the current implementation.
- Real-time events (`order:status_changed`, `rider:location_update`, `delivery:request`, `dispute:resolved`) continue to be delivered immediately to connected clients.

**Scope:**
All inputs that do NOT satisfy any of the 13 bug conditions above must be completely unaffected by these fixes.

---

## Hypothesized Root Cause

1. **Bug 1 — Validator/type mismatch**: `createMenuItemValidation` was written before `CreateMenuItemInput` made `description` optional, and the two were never reconciled.

2. **Bug 2 — Incomplete env.ts**: Three variables present in `.env.example` were never added to the `env` object in `env.ts`, so they are silently ignored at startup.

3. **Bug 3 — Hardcoded Chapa URL**: `refund.service.ts` was written with a literal `hostname` and `path` rather than deriving them from `env.CHAPA_BASE_URL`, likely because that env key did not exist yet (see Bug 2).

4. **Bug 4 — Incomplete riderDeclined**: The function was left in a half-finished state. The inline comment `// We need restaurant/address info — re-trigger via a lightweight re-query` confirms the author knew context was missing. The `dispatchSessions` map only stores `{ startTime, riderIndex, riders, currentTimeout }` — it lacks `restaurant`, `customerAddress`, and `deliveryFee`, so `sendToNextRider` cannot be called from `riderDeclined`.

5. **Bug 5 — Open CORS**: `cors()` was called with no options, which defaults to `Access-Control-Allow-Origin: *`. Origin restriction was deferred and never implemented.

6. **Bug 6 — Missing Order fields**: The `Order` interface and the `orders` table were created before the product requirements for notes, estimated delivery time, and payment method were finalised.

7. **Bug 7 — Missing Restaurant fields**: Same pattern as Bug 6 — `is_open`, `operating_hours`, and `minimum_order_value` were not in the initial schema.

8. **Bug 8 — Missing rider profile endpoints**: The riders router only covers location/availability updates. Profile and document management endpoints were never implemented.

9. **Bug 9 — No rate limiting**: `express-rate-limit` was not added to the project; the package is absent from `package.json`.

10. **Bug 10 — No request logger**: A request-logging middleware was never created or wired into `app.ts`.

11. **Bug 11 — No retry logic**: The raw `https.request` implementation has no retry wrapper; transient errors propagate immediately as rejections.

12. **Bug 12 — No missed-event queue**: `socket.service.ts` emits directly to the room with no buffering; if the room is empty (user offline) the event is discarded.

13. **Bug 13 — No room cleanup**: The `disconnect` handler in `socket.service.ts` only logs; it never calls `socket.leave('user:<id>')`.

---

## Correctness Properties

Property 1: Bug Condition — Description Field Is Optional

_For any_ create-menu-item request where `description` is absent or null (isBugCondition_1 returns true), the fixed `createMenuItemHandler` SHALL accept the request, pass validation, and return HTTP 201 with `description: null` in the response body.

**Validates: Requirements 2.1**

Property 2: Preservation — Description Field With Value

_For any_ create-menu-item request where `description` is a non-empty string (isBugCondition_1 returns false), the fixed handler SHALL produce exactly the same result as the original handler, storing and returning the description unchanged.

**Validates: Requirements 3.1**

Property 3: Bug Condition — Env Vars Are Exposed

_For any_ application startup where `CHAPA_PUBLIC_KEY`, `USE_CLOUDINARY`, or `CHAPA_BASE_URL` are set in the environment (isBugCondition_2 returns true), the fixed `env` object SHALL expose all three with correct types (`string`, `boolean`, `string`).

**Validates: Requirements 2.2**

Property 4: Preservation — Existing Env Vars Unchanged

_For any_ application startup, the fixed `env` object SHALL continue to expose all pre-existing keys with identical types and default values (isBugCondition_2 returns false for existing keys).

**Validates: Requirements 3.2**

Property 5: Bug Condition — Refund Uses Env Base URL

_For any_ refund call where `env.CHAPA_BASE_URL` is set to a non-default value (isBugCondition_3 returns true), the fixed `initiateRefund'` SHALL construct the HTTP request using the hostname and path derived from `env.CHAPA_BASE_URL`.

**Validates: Requirements 2.3**

Property 6: Bug Condition — Rider Declined Triggers Next Rider

_For any_ dispatch event where a rider declines (isBugCondition_4 returns true) and the session has remaining riders and time budget, the fixed `riderDeclined'` SHALL call `sendToNextRider` so the next rider receives a delivery request.

**Validates: Requirements 2.4**

Property 7: Preservation — Rider Accepted Clears Session

_For any_ dispatch event where a rider accepts (isBugCondition_4 returns false), `riderAccepted` SHALL continue to clear the session and cancel the timeout, unchanged.

**Validates: Requirements 3.3**

Property 8: Bug Condition — CORS Rejects Disallowed Origins

_For any_ HTTP request from an origin not in `ALLOWED_ORIGINS` (isBugCondition_5 returns true), the fixed CORS middleware SHALL NOT include `Access-Control-Allow-Origin` for that origin.

**Validates: Requirements 2.5**

Property 9: Preservation — CORS Permits Allowed Origins

_For any_ HTTP request from an origin in `ALLOWED_ORIGINS` (isBugCondition_5 returns false), the fixed CORS middleware SHALL continue to permit the request including preflight OPTIONS.

**Validates: Requirements 3.5**

Property 10: Bug Condition — Order Model Has New Fields

_For any_ Order object (isBugCondition_6 returns true on the old model), the fixed `Order` interface SHALL include `notes`, `estimated_delivery_time`, and `payment_method` as optional/nullable fields.

**Validates: Requirements 2.6**

Property 11: Preservation — Existing Order Fields Unchanged

_For any_ Order object, all pre-existing fields SHALL remain present with identical names and types (isBugCondition_6 returns false for existing fields).

**Validates: Requirements 3.6**

Property 12: Bug Condition — Restaurant Model Has New Fields

_For any_ Restaurant object (isBugCondition_7 returns true on the old model), the fixed `Restaurant` interface SHALL include `is_open`, `operating_hours`, and `minimum_order_value` as optional fields.

**Validates: Requirements 2.7**

Property 13: Preservation — Existing Restaurant Fields Unchanged

_For any_ Restaurant object, all pre-existing fields SHALL remain present with identical names and types.

**Validates: Requirements 3.7**

Property 14: Bug Condition — Rider Profile Endpoints Exist

_For any_ request to `GET /riders/profile` or `PUT /riders/profile` by an authenticated rider (isBugCondition_8 returns true), the fixed router SHALL route the request to a handler that reads/writes rider profile data and returns HTTP 200.

**Validates: Requirements 2.8**

Property 15: Bug Condition — Rate Limiter Returns 429

_For any_ HTTP request where the per-IP request count exceeds the threshold within the window (isBugCondition_9 returns true), the fixed middleware SHALL return HTTP 429 before the request reaches any route handler.

**Validates: Requirements 2.9**

Property 16: Bug Condition — Request Logger Emits Log Line

_For any_ HTTP request (isBugCondition_10 returns true on the unfixed app), the fixed `app.ts` SHALL emit a log line containing method, path, status code, and elapsed milliseconds for every request.

**Validates: Requirements 2.10**

Property 17: Bug Condition — Refund Retries On Transient Error

_For any_ refund call where the first attempt fails with a network error (isBugCondition_11 returns true), the fixed `initiateRefund'` SHALL retry up to 3 times with exponential backoff before rejecting.

**Validates: Requirements 2.11**

Property 18: Preservation — Refund Success Path Unchanged

_For any_ refund call that succeeds on the first attempt (isBugCondition_11 returns false), the fixed service SHALL behave identically to the original.

**Validates: Requirements 3.9**

Property 19: Bug Condition — Missed Events Delivered On Reconnect

_For any_ socket event emitted while a user is offline within the TTL window (isBugCondition_12 returns true), the fixed `socket.service.ts` SHALL queue the event and deliver it when the user reconnects.

**Validates: Requirements 2.12**

Property 20: Preservation — Online Event Delivery Unchanged

_For any_ socket event emitted while the target user is connected (isBugCondition_12 returns false), the fixed service SHALL deliver the event immediately, identical to the original behaviour.

**Validates: Requirements 3.10**

Property 21: Bug Condition — Room Cleanup On Disconnect

_For any_ socket disconnect event (isBugCondition_13 returns true), the fixed disconnect handler SHALL call `socket.leave('user:<userId>')` to release the room reference.

**Validates: Requirements 2.13**

---

## Fix Implementation

### Changes Required

**File 1: `backend/src/controllers/menu.controller.ts`**

- Change `body('description').notEmpty().trim()` → `body('description').optional().trim()` in `createMenuItemValidation`.

**File 2: `backend/src/config/env.ts`**

- Add `CHAPA_PUBLIC_KEY: process.env.CHAPA_PUBLIC_KEY || ''`
- Add `USE_CLOUDINARY: process.env.USE_CLOUDINARY === 'true'`
- Add `CHAPA_BASE_URL: process.env.CHAPA_BASE_URL || 'https://api.chapa.co/v1'`
- Add `ALLOWED_ORIGINS: process.env.ALLOWED_ORIGINS || 'http://localhost:3000,http://localhost:3001'`

**File 3: `backend/src/services/refund.service.ts`**

- Replace `import https from 'https'` with `import axios from 'axios'`.
- Derive `baseUrl` from `env.CHAPA_BASE_URL`.
- Wrap the axios POST in a retry loop: attempt up to 3 times, doubling the delay (100 ms → 200 ms → 400 ms) on each failure, catching only network/5xx errors (not 4xx).

**File 4: `backend/src/services/rider.service.ts`**

- Extend the `dispatchSessions` map value type to include `restaurant: { name: string; address: string }`, `customerAddress: string`, and `deliveryFee: number`.
- In `startDispatch`, store those three values when creating the session entry.
- In `riderDeclined`, after incrementing `session.riderIndex`, call `sendToNextRider(orderId, session.restaurant, session.customerAddress, session.deliveryFee)` directly.

**File 5: `backend/src/app.ts`**

- Import `env` from `./config/env`.
- Replace `app.use(cors())` with a configured cors call that reads `env.ALLOWED_ORIGINS`, splits on `,`, and passes the resulting array as the `origin` whitelist.
- Import and apply `rateLimiter` (global) and `authRateLimiter` (on `/api/v1/auth`) from the new middleware.
- Import and apply `requestLogger` after `requestIdMiddleware`.

**File 6: `backend/src/models/order.model.ts`**

- Add to the `Order` interface: `notes?: string | null`, `estimated_delivery_time?: Date | null`, `payment_method?: string | null`.

**File 7: `backend/src/models/restaurant.model.ts`**

- Add to the `Restaurant` interface: `is_open?: boolean`, `operating_hours?: Record<string, { open: string; close: string }> | null`, `minimum_order_value?: number`.

**File 8: `backend/src/routes/riders.ts`**

- Add `GET /riders/profile` — authenticate + authorize('rider'), query `rider_profiles` (or `users`) for the rider's profile data, return it.
- Add `PUT /riders/profile` — authenticate + authorize('rider'), validate body fields, upsert into `rider_profiles` table, return updated record.

**File 9: `backend/src/middleware/rateLimiter.ts`** _(new file)_

- Export `rateLimiter`: `rateLimit({ windowMs: 15 * 60 * 1000, max: 100 })`.
- Export `authRateLimiter`: `rateLimit({ windowMs: 15 * 60 * 1000, max: 10 })`.

**File 10: `backend/src/middleware/requestLogger.ts`** _(new file)_

- Middleware that records `start = Date.now()` on the way in, then hooks `res.on('finish', ...)` to log `method`, `path`, `statusCode`, and `Date.now() - start` ms.

**File 11: `backend/src/services/socket.service.ts`**

- In the `disconnect` handler, call `socket.leave('user:' + userId)`.
- Add `missedEventQueue: Map<string, Array<{ event: string; payload: unknown; ts: number }>>` module-level.
- Add helper `queueEvent(userId, event, payload)` that pushes to the queue and schedules TTL cleanup.
- Add helper `flushQueue(socket, userId)` that replays queued events in order and clears the queue.
- In the `connection` handler, call `flushQueue(socket, userId)` after joining the room.
- In all `emit*` functions, if `io.sockets.adapter.rooms.get('user:' + targetUserId)` is empty/undefined, call `queueEvent` instead of (or in addition to) emitting.

**File 12: `database/migrations/004_inconsistencies_fix.sql`** _(new file)_

```sql
ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS notes TEXT,
  ADD COLUMN IF NOT EXISTS estimated_delivery_time TIMESTAMP,
  ADD COLUMN IF NOT EXISTS payment_method VARCHAR(50);

ALTER TABLE restaurants
  ADD COLUMN IF NOT EXISTS is_open BOOLEAN DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS operating_hours JSONB,
  ADD COLUMN IF NOT EXISTS minimum_order_value DECIMAL(10,2) DEFAULT 0;

CREATE TABLE IF NOT EXISTS rider_profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rider_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  license_number VARCHAR(100),
  vehicle_type VARCHAR(50),
  vehicle_plate VARCHAR(50),
  document_url TEXT,
  verified BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(rider_id)
);
```

**Packages to install:**

```bash
npm install axios express-rate-limit
npm install --save-dev @types/express-rate-limit
```

---

## Testing Strategy

### Validation Approach

Testing follows a two-phase approach: first surface counterexamples on unfixed code to confirm root cause analysis, then verify the fix and preservation properties.

---

### Exploratory Bug Condition Checking

**Goal**: Demonstrate each bug on the unfixed codebase before applying any fix.

**Test Plan**: Write unit/integration tests that exercise each bug condition and assert the correct (post-fix) behaviour. Run against unfixed code to observe failures and confirm root causes.

**Test Cases**:

1. **Description Validation**: POST create-menu-item without `description` → assert HTTP 201 (will fail: gets 422 on unfixed code).
2. **Env Vars Exposed**: Import `env` and assert `env.CHAPA_PUBLIC_KEY`, `env.USE_CLOUDINARY`, `env.CHAPA_BASE_URL` are defined (will fail on unfixed code).
3. **Refund Uses Env URL**: Set `CHAPA_BASE_URL=https://sandbox.chapa.co/v1`, call `initiateRefund`, intercept HTTP call, assert hostname is `sandbox.chapa.co` (will fail on unfixed code).
4. **Rider Declined Dispatches Next**: Call `riderDeclined(orderId)` on a session with 2 riders, assert `emitDeliveryRequest` is called for rider 2 (will fail on unfixed code).
5. **CORS Rejects Unknown Origin**: Send request with `Origin: https://evil.example.com`, assert no `Access-Control-Allow-Origin` header (will fail on unfixed code).
6. **Rate Limiter 429**: Send 11 rapid requests to `/api/v1/auth/login`, assert 11th returns 429 (will fail on unfixed code).
7. **Request Logger Emits**: Make any request, assert logger was called with method/path/status/ms (will fail on unfixed code).
8. **Refund Retry**: Mock axios to fail twice then succeed, assert `initiateRefund` resolves (will fail on unfixed code).
9. **Missed Event Queue**: Emit `order:status_changed` to an offline user, reconnect, assert event is received (will fail on unfixed code).
10. **Room Cleanup**: Connect socket, disconnect, assert `user:<id>` room is empty (will fail on unfixed code).

**Expected Counterexamples**:
- Validation rejects valid requests; env keys are undefined; refund hits wrong host; dispatch stalls; CORS is open; no 429; no log lines; no retries; events lost; rooms leak.

---

### Fix Checking

**Goal**: Verify that for all inputs where each bug condition holds, the fixed code produces the expected behaviour.

**Pseudocode:**
```
FOR ALL X WHERE isBugCondition_N(X) DO
  result := fixedFunction(X)
  ASSERT property_N(result)
END FOR
```

---

### Preservation Checking

**Goal**: Verify that for all inputs where the bug condition does NOT hold, the fixed code produces the same result as the original.

**Pseudocode:**
```
FOR ALL X WHERE NOT isBugCondition_N(X) DO
  ASSERT originalFunction(X) = fixedFunction(X)
END FOR
```

**Testing Approach**: Property-based testing (fast-check, already in devDependencies) is used for preservation checking because it generates many input combinations automatically and catches edge cases that manual tests miss.

**Test Cases**:
1. **Description With Value**: Generate random non-empty description strings, assert create-menu-item still returns 201 with the description stored.
2. **Existing Env Keys**: Assert all pre-existing env keys remain defined with correct types after adding new ones.
3. **Refund First-Attempt Success**: Mock axios to succeed immediately, assert behaviour is identical to original (single call, log, resolve).
4. **Rider Accepted**: Call `riderAccepted` after a session is created, assert session is deleted and timeout is cleared.
5. **Allowed Origins Pass CORS**: Generate requests from `ALLOWED_ORIGINS` list, assert all receive correct ACAO header.
6. **Existing Order Fields**: Construct Order objects, assert all 16 pre-existing fields are present and typed correctly.
7. **Existing Restaurant Fields**: Construct Restaurant objects, assert all 14 pre-existing fields are present and typed correctly.
8. **Existing Rider Endpoints**: Call `PUT /riders/location` and `PUT /riders/availability`, assert they continue to return 200.
9. **Online Socket Events**: Emit events to connected users, assert immediate delivery (no queuing).

---

### Unit Tests

- Validate `createMenuItemValidation` accepts requests with and without `description`.
- Assert `env.CHAPA_PUBLIC_KEY`, `env.USE_CLOUDINARY` (boolean), `env.CHAPA_BASE_URL`, `env.ALLOWED_ORIGINS` are correctly parsed.
- Assert `initiateRefund` constructs the URL from `env.CHAPA_BASE_URL`.
- Assert `riderDeclined` calls `sendToNextRider` (spy/mock) with correct context.
- Assert `rateLimiter` middleware returns 429 after threshold is exceeded.
- Assert `requestLogger` middleware logs method, path, status, and elapsed ms.
- Assert `initiateRefund` retries up to 3 times on network error and succeeds on the 3rd attempt.
- Assert `socket.service` queues events for offline users and flushes on reconnect.
- Assert `socket.service` calls `socket.leave` on disconnect.

### Property-Based Tests

- Generate arbitrary `CreateMenuItemRequest` objects with and without `description`; assert validation result matches expected (optional field).
- Generate arbitrary origin strings; assert CORS allows only those in `ALLOWED_ORIGINS`.
- Generate arbitrary dispatch sequences (accept/decline/timeout); assert session state is always consistent.
- Generate arbitrary sequences of connect/disconnect/emit; assert no events are delivered after TTL expires and all events within TTL are delivered on reconnect.

### Integration Tests

- Full create-menu-item flow without `description` → assert item is created with `description: null` in DB.
- Full rider dispatch flow: start dispatch → rider 1 declines → assert rider 2 receives request.
- Full refund flow with simulated transient failure → assert refund eventually succeeds after retries.
- Full request lifecycle → assert log line appears in logger output.
- Auth endpoint flood test → assert 429 is returned after 10 requests within 15 minutes.
