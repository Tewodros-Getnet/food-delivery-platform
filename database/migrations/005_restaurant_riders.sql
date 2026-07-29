-- Migration: 005_restaurant_riders.sql
-- Creates restaurant_riders table for exclusive rider-restaurant assignment.
-- PRIMARY KEY on rider_id enforces one-restaurant-per-rider at DB level.

CREATE TABLE IF NOT EXISTS restaurant_riders (
  rider_id     UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  restaurant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  joined_at    TIMESTAMP DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_restaurant_riders_restaurant_id
  ON restaurant_riders(restaurant_id);

-- Pending invitations: restaurant invites a rider by email before they accept
CREATE TABLE IF NOT EXISTS rider_invitations (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  rider_email   VARCHAR(255) NOT NULL,
  status        VARCHAR(20) DEFAULT 'pending'
                CHECK (status IN ('pending', 'accepted', 'declined')),
  created_at    TIMESTAMP DEFAULT NOW(),
  UNIQUE(restaurant_id, rider_email)
);

CREATE INDEX IF NOT EXISTS idx_rider_invitations_email
  ON rider_invitations(rider_email);
