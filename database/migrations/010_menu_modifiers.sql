-- Migration 010: Menu Item Modifiers
-- Adds modifier groups to menu items and selected modifiers to order items

-- Add modifiers JSONB column to menu_items
-- Format: [{ "name": "Size", "type": "single", "required": true, "options": [{ "name": "Small", "price": 0 }, { "name": "Large", "price": 20 }] }]
ALTER TABLE menu_items
  ADD COLUMN IF NOT EXISTS modifiers JSONB DEFAULT '[]'::jsonb;

-- Add selected_modifiers JSONB column to order_items
-- Format: [{ "group": "Size", "option": "Large", "price": 20 }]
ALTER TABLE order_items
  ADD COLUMN IF NOT EXISTS selected_modifiers JSONB DEFAULT '[]'::jsonb;
