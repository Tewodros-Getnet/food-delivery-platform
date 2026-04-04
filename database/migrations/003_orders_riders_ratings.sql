-- Migration 003: Orders, Riders, Ratings, Disputes, Config, FCM

-- Orders
CREATE TABLE orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id UUID NOT NULL REFERENCES users(id),
  restaurant_id UUID NOT NULL REFERENCES restaurants(id),
  rider_id UUID REFERENCES users(id),
  delivery_address_id UUID NOT NULL REFERENCES addresses(id),
  status VARCHAR(30) NOT NULL CHECK (status IN (
    'pending_payment', 'payment_failed', 'confirmed',
    'ready_for_pickup', 'rider_assigned', 'picked_up',
    'delivered', 'cancelled'
  )),
  subtotal DECIMAL(10, 2) NOT NULL,
  delivery_fee DECIMAL(10, 2) NOT NULL,
  total DECIMAL(10, 2) NOT NULL,
  payment_reference VARCHAR(255),
  payment_status VARCHAR(20),
  cancellation_reason TEXT,
  cancelled_at TIMESTAMP,
  estimated_prep_time_minutes INT,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);
CREATE INDEX idx_orders_customer_id ON orders(customer_id);
CREATE INDEX idx_orders_restaurant_id ON orders(restaurant_id);
CREATE INDEX idx_orders_rider_id ON orders(rider_id);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_orders_created_at ON orders(created_at);

-- Order Items
CREATE TABLE order_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  menu_item_id UUID NOT NULL REFERENCES menu_items(id),
  quantity INT NOT NULL CHECK (quantity > 0),
  unit_price DECIMAL(10, 2) NOT NULL,
  item_name VARCHAR(255) NOT NULL,
  item_image_url TEXT
);
CREATE INDEX idx_order_items_order_id ON order_items(order_id);

-- Rider Locations
CREATE TABLE rider_locations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rider_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  latitude DECIMAL(10, 8) NOT NULL,
  longitude DECIMAL(11, 8) NOT NULL,
  availability VARCHAR(20) NOT NULL CHECK (availability IN ('available', 'on_delivery', 'offline')),
  timestamp TIMESTAMP DEFAULT NOW()
);
CREATE INDEX idx_rider_locations_rider_id ON rider_locations(rider_id);
CREATE INDEX idx_rider_locations_timestamp ON rider_locations(timestamp);
CREATE INDEX idx_rider_locations_availability ON rider_locations(availability);

-- Ratings
CREATE TABLE ratings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  customer_id UUID NOT NULL REFERENCES users(id),
  restaurant_id UUID REFERENCES restaurants(id),
  rider_id UUID REFERENCES users(id),
  rating INT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  review TEXT,
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(order_id, restaurant_id),
  UNIQUE(order_id, rider_id)
);
CREATE INDEX idx_ratings_restaurant_id ON ratings(restaurant_id);
CREATE INDEX idx_ratings_rider_id ON ratings(rider_id);

-- Disputes
CREATE TABLE disputes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES orders(id),
  customer_id UUID NOT NULL REFERENCES users(id),
  reason TEXT NOT NULL,
  evidence_url TEXT,
  status VARCHAR(20) DEFAULT 'open' CHECK (status IN ('open', 'resolved')),
  resolution VARCHAR(50) CHECK (resolution IN ('refund', 'partial_refund', 'no_action')),
  refund_amount DECIMAL(10, 2),
  admin_notes TEXT,
  created_at TIMESTAMP DEFAULT NOW(),
  resolved_at TIMESTAMP
);
CREATE INDEX idx_disputes_status ON disputes(status);
CREATE INDEX idx_disputes_order_id ON disputes(order_id);

-- Platform Config
CREATE TABLE platform_config (
  key VARCHAR(100) PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TIMESTAMP DEFAULT NOW()
);
INSERT INTO platform_config (key, value) VALUES
  ('delivery_base_fee', '5.00'),
  ('delivery_rate_per_km', '2.00'),
  ('rider_search_radius_km', '5.0'),
  ('rider_timeout_seconds', '60'),
  ('dispatch_max_duration_minutes', '10');

-- FCM Tokens
CREATE TABLE fcm_tokens (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  token TEXT NOT NULL,
  device_type VARCHAR(20) CHECK (device_type IN ('ios', 'android', 'web')),
  created_at TIMESTAMP DEFAULT NOW(),
  UNIQUE(user_id, token)
);
CREATE INDEX idx_fcm_tokens_user_id ON fcm_tokens(user_id);
