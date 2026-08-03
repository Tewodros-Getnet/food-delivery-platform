-- Add rejection_reason column to restaurants table
-- Stores the admin-provided reason when a restaurant application is rejected

ALTER TABLE restaurants
  ADD COLUMN IF NOT EXISTS rejection_reason TEXT DEFAULT NULL;
