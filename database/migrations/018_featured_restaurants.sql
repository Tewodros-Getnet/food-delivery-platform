 -- Migration 018: Featured Restaurants
-- Adds featured_until column to restaurants table.
-- When featured_until is a future timestamp the restaurant is considered
-- "featured" and will appear in the featured section on the customer home screen.
-- Managed by admins via the admin dashboard.

ALTER TABLE restaurants
  ADD COLUMN IF NOT EXISTS featured_until TIMESTAMPTZ DEFAULT NULL;

-- Index so the backend can cheaply query currently-featured restaurants
CREATE INDEX IF NOT EXISTS idx_restaurants_featured_until
  ON restaurants (featured_until)
  WHERE featured_until IS NOT NULL;
