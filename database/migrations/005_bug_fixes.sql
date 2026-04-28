-- Migration: 005_bug_fixes.sql
-- Fixes: Bug 1 (rider_locations UNIQUE), Bug 2 (dispatch session tables),
--        Bug 5 (cancelled_by 'system' support)
-- All DDL is idempotent (IF NOT EXISTS / DROP CONSTRAINT IF EXISTS).

-- ── Bug 1: Deduplicate rider_locations, then add UNIQUE constraint ────────────
-- Remove duplicate rows, keeping the latest row per rider_id by timestamp.
DELETE FROM rider_locations
WHERE id NOT IN (
  SELECT DISTINCT ON (rider_id) id
  FROM rider_locations
  ORDER BY rider_id, timestamp DESC
);

ALTER TABLE rider_locations
  DROP CONSTRAINT IF EXISTS rider_locations_rider_id_key;

ALTER TABLE rider_locations
  ADD CONSTRAINT rider_locations_rider_id_key UNIQUE (rider_id);

-- ── Bug 2: Dispatch session persistence tables ────────────────────────────────
CREATE TABLE IF NOT EXISTS dispatch_sessions (
  order_id         UUID PRIMARY KEY REFERENCES orders(id) ON DELETE CASCADE,
  rider_index      INT           NOT NULL DEFAULT 0,
  riders           JSONB         NOT NULL,
  restaurant       JSONB         NOT NULL,
  customer_address TEXT          NOT NULL,
  delivery_fee     DECIMAL(10,2) NOT NULL,
  start_time       BIGINT        NOT NULL,
  created_at       TIMESTAMP     DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS retry_sessions_no_rider (
  order_id             UUID PRIMARY KEY REFERENCES orders(id) ON DELETE CASCADE,
  retry_count          INT  NOT NULL DEFAULT 0,
  restaurant_id        UUID NOT NULL REFERENCES restaurants(id),
  customer_id          UUID NOT NULL REFERENCES users(id),
  restaurant_owner_id  UUID NOT NULL REFERENCES users(id),
  created_at           TIMESTAMP DEFAULT NOW()
);

-- ── Bug 5: Extend cancelled_by CHECK constraint to include 'system' ───────────
ALTER TABLE orders
  DROP CONSTRAINT IF EXISTS orders_cancelled_by_check;

ALTER TABLE orders
  ADD CONSTRAINT orders_cancelled_by_check
    CHECK (cancelled_by IN ('customer', 'restaurant', 'admin', 'system'));
