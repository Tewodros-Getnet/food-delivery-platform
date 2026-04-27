-- Migration 012: Promotional Banners
-- Adds promo_banner_text and promo_banner_image_url to restaurants

ALTER TABLE restaurants
  ADD COLUMN IF NOT EXISTS promo_banner_text VARCHAR(120),
  ADD COLUMN IF NOT EXISTS promo_banner_image_url TEXT;
