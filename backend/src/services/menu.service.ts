import { query } from '../config/database';
import { MenuItem } from '../models/menu.model';
import { uploadImage } from './cloudinary.service';

export interface CreateMenuItemInput {
  restaurantId: string;
  name: string;
  description?: string;
  price: number;
  category: string;
  imageBase64: string;
}

export async function createMenuItem(input: CreateMenuItemInput): Promise<MenuItem> {
  const image_url = await uploadImage(input.imageBase64, 'menu_items');

  const result = await query<MenuItem>(
    `INSERT INTO menu_items (restaurant_id, name, description, price, category, image_url)
     VALUES ($1,$2,$3,$4,$5,$6) RETURNING *`,
    [input.restaurantId, input.name, input.description ?? null, input.price, input.category, image_url]
  );
  return result.rows[0];
}

export async function getMenuItems(params: {
  restaurantId: string;
  category?: string;
  customerView?: boolean;
}): Promise<MenuItem[]> {
  const conditions = ['restaurant_id = $1'];
  const values: unknown[] = [params.restaurantId];
  let idx = 2;

  if (params.customerView) {
    conditions.push('available = TRUE');
  }
  if (params.category) {
    conditions.push(`category ILIKE $${idx++}`);
    values.push(params.category);
  }

  const result = await query<MenuItem>(
    `SELECT * FROM menu_items WHERE ${conditions.join(' AND ')} ORDER BY category, name`,
    values
  );
  return result.rows;
}

export async function getMenuItemById(id: string): Promise<MenuItem | null> {
  const result = await query<MenuItem>('SELECT * FROM menu_items WHERE id = $1', [id]);
  return result.rows[0] ?? null;
}

export async function updateMenuItem(
  id: string,
  updates: Partial<Pick<MenuItem, 'name' | 'description' | 'price' | 'category' | 'available'>>
): Promise<MenuItem | null> {
  const fields: string[] = [];
  const values: unknown[] = [];
  let idx = 1;

  if (updates.name !== undefined) { fields.push(`name = $${idx++}`); values.push(updates.name); }
  if (updates.description !== undefined) { fields.push(`description = $${idx++}`); values.push(updates.description); }
  if (updates.price !== undefined) { fields.push(`price = $${idx++}`); values.push(updates.price); }
  if (updates.category !== undefined) { fields.push(`category = $${idx++}`); values.push(updates.category); }
  if (updates.available !== undefined) { fields.push(`available = $${idx++}`); values.push(updates.available); }

  if (fields.length === 0) return getMenuItemById(id);

  fields.push(`updated_at = NOW()`);
  values.push(id);

  const result = await query<MenuItem>(
    `UPDATE menu_items SET ${fields.join(', ')} WHERE id = $${idx} RETURNING *`,
    values
  );
  return result.rows[0] ?? null;
}

export async function deleteMenuItem(id: string): Promise<{ deleted: boolean; markedUnavailable: boolean }> {
  // Check if item is in any active order
  const activeOrder = await query(
    `SELECT 1 FROM order_items oi
     JOIN orders o ON o.id = oi.order_id
     WHERE oi.menu_item_id = $1
     AND o.status NOT IN ('delivered', 'cancelled', 'payment_failed')
     LIMIT 1`,
    [id]
  );

  if (activeOrder.rowCount && activeOrder.rowCount > 0) {
    await query(`UPDATE menu_items SET available = FALSE, updated_at = NOW() WHERE id = $1`, [id]);
    return { deleted: false, markedUnavailable: true };
  }

  await query('DELETE FROM menu_items WHERE id = $1', [id]);
  return { deleted: true, markedUnavailable: false };
}

export async function toggleAvailability(id: string): Promise<MenuItem | null> {
  const result = await query<MenuItem>(
    `UPDATE menu_items SET available = NOT available, updated_at = NOW() WHERE id = $1 RETURNING *`,
    [id]
  );
  return result.rows[0] ?? null;
}
