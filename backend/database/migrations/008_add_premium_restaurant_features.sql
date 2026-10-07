-- Migration: Add premium/subscription features for restaurants
-- File: 008_add_premium_restaurant_features.sql

-- Add subscription and promotion fields to restaurants table
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS subscription_tier VARCHAR(20) DEFAULT 'free';
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS subscription_expires_at TIMESTAMP;
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS is_promoted BOOLEAN DEFAULT false;
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS promotion_expires_at TIMESTAMP;
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS boost_score INTEGER DEFAULT 0;
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS featured_until TIMESTAMP;

-- Add comments for clarity
COMMENT ON COLUMN restaurants.subscription_tier IS 'free, premium, premium_plus';
COMMENT ON COLUMN restaurants.subscription_expires_at IS 'When current subscription expires';
COMMENT ON COLUMN restaurants.is_promoted IS 'Currently running paid promotion';
COMMENT ON COLUMN restaurants.promotion_expires_at IS 'When current promotion expires';
COMMENT ON COLUMN restaurants.boost_score IS 'Paid boost ranking score (0-100)';
COMMENT ON COLUMN restaurants.featured_until IS 'Featured in special sections until this time';

-- Create index for efficient premium restaurant queries
CREATE INDEX IF NOT EXISTS idx_restaurants_subscription ON restaurants(subscription_tier, subscription_expires_at);
CREATE INDEX IF NOT EXISTS idx_restaurants_promoted ON restaurants(is_promoted, promotion_expires_at);
CREATE INDEX IF NOT EXISTS idx_restaurants_boost ON restaurants(boost_score DESC);
CREATE INDEX IF NOT EXISTS idx_restaurants_featured ON restaurants(featured_until);

-- Create subscription plans table for management
CREATE TABLE IF NOT EXISTS restaurant_subscription_plans (
    id SERIAL PRIMARY KEY,
    name VARCHAR(50) NOT NULL,
    price_per_month DECIMAL(10,2) NOT NULL,
    max_promotions_per_month INTEGER DEFAULT 0,
    boost_score_multiplier DECIMAL(3,2) DEFAULT 1.0,
    can_be_featured BOOLEAN DEFAULT false,
    search_priority_boost INTEGER DEFAULT 0,
    description TEXT,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Insert default subscription plans
INSERT INTO restaurant_subscription_plans (name, price_per_month, max_promotions_per_month, boost_score_multiplier, can_be_featured, search_priority_boost, description)
VALUES 
    ('Free', 0.00, 0, 1.0, false, 0, 'Basic listing with standard search placement'),
    ('Premium', 99.00, 10, 2.0, true, 10, 'Enhanced visibility with promotion options and featured placement'),
    ('Premium Plus', 299.00, 30, 5.0, true, 50, 'Maximum visibility with unlimited promotions and top search priority')
ON CONFLICT DO NOTHING;