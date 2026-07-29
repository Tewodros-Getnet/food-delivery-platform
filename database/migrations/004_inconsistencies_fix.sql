-- Migration: 004_inconsistencies_fix.sql
-- Adds missing fields to orders and restaurants, and creates rider_profiles table.
-- All changes use IF NOT EXISTS / ADD COLUMN IF NOT EXISTS to be safe on re-run.

-- ── Orders: add notes, estimated_delivery_time, payment_method ────────────────
ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS notes TEXT,
  ADD COLUMN IF NOT EXISTS estimated_delivery_time TIMESTAMP,
  ADD COLUMN IF NOT EXISTS payment_method VARCHAR(50);

-- ── Restaurants: add is_open, operating_hours, minimum_order_value ────────────
ALTER TABLE restaurants
  ADD COLUMN IF NOT EXISTS is_open BOOLEAN DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS operating_hours JSONB,
  ADD COLUMN IF NOT EXISTS minimum_order_value DECIMAL(10,2) DEFAULT 0;

-- ── Rider profiles table ──────────────────────────────────────────────────────
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
