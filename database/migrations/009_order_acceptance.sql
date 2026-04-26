-- Migration 009: Restaurant Order Acceptance
-- Adds pending_acceptance status, acceptance_deadline column, and config key

-- 1. Drop existing status CHECK constraint and recreate with pending_acceptance
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

-- 2. Add acceptance_deadline column (null for orders that don't go through this flow)
ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS acceptance_deadline TIMESTAMP;

-- 3. Partial index for efficient scheduler queries on expired pending_acceptance orders
CREATE INDEX IF NOT EXISTS idx_orders_acceptance_deadline
  ON orders(acceptance_deadline)
  WHERE status = 'pending_acceptance';

-- 4. Add acceptance timeout config (default 3 minutes = 180 seconds)
INSERT INTO platform_config (key, value)
VALUES ('order_acceptance_timeout_seconds', '180')
ON CONFLICT (key) DO NOTHING;
