# Bugfix Requirements Document

## Introduction

The food delivery backend (Node.js/TypeScript) has accumulated a set of inconsistencies and missing pieces across validation, configuration, dispatch logic, security, data models, and infrastructure services. Left unaddressed these issues range from silent runtime failures (broken rider re-dispatch, hardcoded URLs) to security risks (open CORS, no rate limiting) and potential memory leaks (Socket.io room accumulation). All fixes must be surgical and non-breaking — existing working behaviour must be fully preserved.

---

## Bug Analysis

### Current Behavior (Defect)

1.1 WHEN a client submits a create-menu-item request with no `description` field THEN the system rejects it with a validation error because `menu.controller.ts` marks `description` as `notEmpty()`, even though `CreateMenuItemInput` in `menu.service.ts` declares it optional.

1.2 WHEN the application starts THEN `env.ts` does not expose `CHAPA_PUBLIC_KEY`, `USE_CLOUDINARY`, or `CHAPA_BASE_URL`, so those values from `.env.example` are silently ignored and unavailable to the rest of the codebase.

1.3 WHEN `refund.service.ts` constructs the Chapa refund request THEN it hardcodes `hostname: 'api.chapa.co'` and `path: '/v1/transaction/refund'` instead of reading `CHAPA_BASE_URL` from the environment, making the base URL impossible to override without a code change.

1.4 WHEN a rider declines a delivery request THEN `riderDeclined()` in `rider.service.ts` increments `session.riderIndex` but never calls `sendToNextRider()`, so dispatch stalls and no subsequent rider is ever contacted (the inline comment acknowledges this is unfinished).

1.5 WHEN the backend is deployed to production THEN `app.ts` initialises CORS with `cors()` and no configuration, allowing requests from any origin.

1.6 WHEN a customer places an order THEN the `Order` model has no `notes` field for special instructions, no `estimated_delivery_time`, and no `payment_method` field, so that information cannot be stored or surfaced.

1.7 WHEN a restaurant is fetched THEN the `Restaurant` model has no `is_open` flag, no `operating_hours`, and no `minimum_order_value`, so customers cannot tell whether a restaurant is currently accepting orders.

1.8 WHEN a rider registers or updates their profile THEN there is no endpoint to submit or update profile/document verification data; only location and availability updates exist.

1.9 WHEN any endpoint receives a high volume of requests THEN there is no rate limiting, leaving authentication endpoints and all other routes open to brute-force and denial-of-service attacks.

1.10 WHEN any HTTP request is processed THEN there is no request-logging middleware that records method, path, status code, and response time, making performance analysis and debugging difficult.

1.11 WHEN `refund.service.ts` calls the Chapa refund API THEN it uses the raw Node.js `https` module with no retry logic, so a transient network error causes the refund to fail permanently with no recovery attempt.

1.12 WHEN a Socket.io client disconnects and then reconnects THEN events emitted during the disconnection window are lost because there is no message queue or missed-event replay mechanism.

1.13 WHEN Socket.io rooms accumulate over time (e.g. `user:<id>` rooms for users who never reconnect) THEN they are never cleaned up, creating a potential memory leak at scale.

---

### Expected Behavior (Correct)

2.1 WHEN a client submits a create-menu-item request with no `description` field THEN the system SHALL accept the request and store `null` for description, consistent with `CreateMenuItemInput` marking it optional.

2.2 WHEN the application starts THEN `env.ts` SHALL expose `CHAPA_PUBLIC_KEY`, `USE_CLOUDINARY` (as a boolean), and `CHAPA_BASE_URL` so all three values are available throughout the codebase.

2.3 WHEN `refund.service.ts` constructs the Chapa refund request THEN it SHALL derive the base URL from `env.CHAPA_BASE_URL` rather than hardcoding it, so the endpoint can be changed via environment variable alone.

2.4 WHEN a rider declines a delivery request THEN `riderDeclined()` SHALL increment the rider index and immediately call `sendToNextRider()` with the necessary context so dispatch continues to the next available rider without interruption.

2.5 WHEN the backend is deployed THEN CORS SHALL be configured to allow only origins listed in an `ALLOWED_ORIGINS` environment variable (defaulting to `localhost` origins in development), rejecting all other origins in production.

2.6 WHEN a customer places an order THEN the `Order` model SHALL include a `notes` field (optional string for special instructions), an `estimated_delivery_time` field (optional timestamp), and a `payment_method` field (optional string).

2.7 WHEN a restaurant is fetched THEN the `Restaurant` model SHALL include an `is_open` boolean, an `operating_hours` field (JSON/object), and a `minimum_order_value` numeric field so clients can determine ordering eligibility.

2.8 WHEN a rider needs to submit or update their profile or verification documents THEN a dedicated endpoint SHALL exist to accept and persist that data.

2.9 WHEN any endpoint receives requests THEN rate-limiting middleware SHALL be applied globally, with stricter limits on authentication endpoints, returning HTTP 429 when limits are exceeded.

2.10 WHEN any HTTP request is processed THEN request-logging middleware SHALL record the method, path, status code, and elapsed time for every request.

2.11 WHEN a Chapa refund API call fails due to a transient error THEN `refund.service.ts` SHALL retry the request up to a configurable number of times with exponential back-off before giving up and logging the failure.

2.12 WHEN a Socket.io client reconnects after a disconnection THEN the server SHALL deliver any events that were emitted while the client was offline, up to a configurable retention window.

2.13 WHEN a Socket.io user room is no longer needed THEN the server SHALL clean it up to prevent unbounded memory growth.

---

### Unchanged Behavior (Regression Prevention)

3.1 WHEN a client submits a create-menu-item request WITH a valid `description` value THEN the system SHALL CONTINUE TO accept and store the description as before.

3.2 WHEN `env.ts` is loaded THEN it SHALL CONTINUE TO expose all existing environment variables (`CHAPA_SECRET_KEY`, `CHAPA_WEBHOOK_SECRET`, `CLOUDINARY_*`, `FIREBASE_*`, rider/dispatch constants, etc.) with the same keys and types.

3.3 WHEN a rider accepts a delivery request THEN `riderAccepted()` SHALL CONTINUE TO clear the dispatch session and cancel any pending timeout as before.

3.4 WHEN the dispatch timeout fires naturally (rider does not respond) THEN `sendToNextRider()` SHALL CONTINUE TO advance to the next rider as before.

3.5 WHEN requests arrive from allowed origins THEN CORS SHALL CONTINUE TO permit them, including preflight OPTIONS requests.

3.6 WHEN an order is created or queried THEN all existing `Order` fields (`id`, `customer_id`, `restaurant_id`, `rider_id`, `delivery_address_id`, `status`, `subtotal`, `delivery_fee`, `total`, `payment_reference`, `payment_status`, `cancellation_reason`, `cancelled_at`, `estimated_prep_time_minutes`, `created_at`, `updated_at`) SHALL CONTINUE TO be present and behave identically.

3.7 WHEN a restaurant is created or queried THEN all existing `Restaurant` fields (`id`, `owner_id`, `name`, `description`, `logo_url`, `cover_image_url`, `address`, `latitude`, `longitude`, `category`, `status`, `average_rating`, `created_at`, `updated_at`) SHALL CONTINUE TO be present and behave identically.

3.8 WHEN a rider updates their location or availability THEN the existing `/riders/location` and `/riders/availability` endpoints SHALL CONTINUE TO function without change.

3.9 WHEN a Chapa refund succeeds on the first attempt THEN the behaviour SHALL CONTINUE TO be identical to the current implementation (single call, log response, resolve).

3.10 WHEN Socket.io clients are connected and online THEN real-time events (`order:status_changed`, `rider:location_update`, `delivery:request`, `dispute:resolved`) SHALL CONTINUE TO be delivered immediately as before.

---

## Bug Condition Pseudocode

### 1 — Description Validation Mismatch

```pascal
FUNCTION isBugCondition_1(X)
  INPUT: X of type CreateMenuItemRequest
  OUTPUT: boolean
  RETURN X.description IS NULL OR X.description IS UNDEFINED
END FUNCTION

// Fix Checking
FOR ALL X WHERE isBugCondition_1(X) DO
  result ← createMenuItem'(X)
  ASSERT result.status = 201 AND result.body.description = null
END FOR

// Preservation Checking
FOR ALL X WHERE NOT isBugCondition_1(X) DO
  ASSERT createMenuItem(X) = createMenuItem'(X)
END FOR
```

### 2 & 3 — Missing / Hardcoded Env Vars

```pascal
FUNCTION isBugCondition_2(E)
  INPUT: E of type EnvConfig
  OUTPUT: boolean
  RETURN E.CHAPA_BASE_URL IS UNDEFINED
      OR E.CHAPA_PUBLIC_KEY IS UNDEFINED
      OR E.USE_CLOUDINARY IS UNDEFINED
END FUNCTION

FOR ALL E WHERE isBugCondition_2(E) DO
  ASSERT env'.CHAPA_BASE_URL IS DEFINED
  ASSERT env'.CHAPA_PUBLIC_KEY IS DEFINED
  ASSERT env'.USE_CLOUDINARY IS DEFINED (boolean)
  ASSERT refundService' uses env'.CHAPA_BASE_URL for hostname/path
END FOR
```

### 4 — Broken Rider Re-dispatch

```pascal
FUNCTION isBugCondition_4(X)
  INPUT: X of type DispatchEvent
  OUTPUT: boolean
  RETURN X.event = 'riderDeclined'
END FUNCTION

FOR ALL X WHERE isBugCondition_4(X) DO
  riderDeclined'(X.orderId)
  ASSERT nextRiderWasContacted(X.orderId) = true
END FOR
```

### 9 — No Rate Limiting

```pascal
FUNCTION isBugCondition_9(X)
  INPUT: X of type HttpRequest
  OUTPUT: boolean
  RETURN requestCountInWindow(X.ip, X.path) > RATE_LIMIT_THRESHOLD
END FUNCTION

FOR ALL X WHERE isBugCondition_9(X) DO
  result ← handleRequest'(X)
  ASSERT result.status = 429
END FOR
```
