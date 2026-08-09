-- Allow menu items to be deleted even when referenced by historical orders.
-- Order items already snapshot item_name, unit_price, and quantity at order time
-- so setting menu_item_id to NULL on delete doesn't lose any order history.

ALTER TABLE order_items
  DROP CONSTRAINT IF EXISTS order_items_menu_item_id_fkey;

ALTER TABLE order_items
  ALTER COLUMN menu_item_id DROP NOT NULL;

ALTER TABLE order_items
  ADD CONSTRAINT order_items_menu_item_id_fkey
  FOREIGN KEY (menu_item_id)
  REFERENCES menu_items(id)
  ON DELETE SET NULL;
