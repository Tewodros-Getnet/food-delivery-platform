-- Migration: 007_restaurant_cancellation.sql
-- Adds cancelled_by column to orders to track which actor cancelled the order.

ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS cancelled_by VARCHAR(20)
    CHECK (cancelled_by IN ('customer', 'restaurant', 'admin'));

CREATE INDEX IF NOT EXISTS idx_orders_cancelled_by ON orders(cancelled_by);
