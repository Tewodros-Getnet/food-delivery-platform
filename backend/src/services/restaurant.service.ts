import { query, withTransaction } from '../config/database';
import { Restaurant, RestaurantStatus } from '../models/restaurant.model';
import { uploadImage } from './cloudinary.service';

export interface CreateRestaurantInput {
  ownerId: string;
  name: string;
  description?: string;
  address: string;
  latitude: number;
  longitude: number;
  category?: string;
  logoBase64?: string;
  coverBase64?: string;
}

export async function createRestaurant(input: CreateRestaurantInput): Promise<Restaurant> {
  let logo_url: string | null = null;
  let cover_image_url: string | null = null;

  if (input.logoBase64) {
    logo_url = await uploadImage(input.logoBase64, 'restaurants/logos');
  }
  if (input.coverBase64) {
    cover_image_url = await uploadImage(input.coverBase64, 'restaurants/covers');
  }

  const result = await query<Restaurant>(
    `INSERT INTO restaurants (owner_id, name, description, address, latitude, longitude, category, logo_url, cover_image_url)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING *`,
    [input.ownerId, input.name, input.description ?? null, input.address,
     input.latitude, input.longitude, input.category ?? null, logo_url, cover_image_url]
  );
  return result.rows[0];
}

export async function getRestaurants(params: {
  category?: string;
  page?: number;
  limit?: number;
}): Promise<{ restaurants: Restaurant[]; total: number }> {
  const page = params.page ?? 1;
  const limit = params.limit ?? 20;
  const offset = (page - 1) * limit;

  const conditions = ["status = 'approved'"];
  const values: unknown[] = [];
  let idx = 1;

  if (params.category) {
    conditions.push(`category ILIKE $${idx++}`);
    values.push(params.category);
  }

  const where = conditions.join(' AND ');
  values.push(limit, offset);

  const [dataResult, countResult] = await Promise.all([
    query<Restaurant>(
      `SELECT * FROM restaurants WHERE ${where} ORDER BY average_rating DESC LIMIT $${idx} OFFSET $${idx + 1}`,
      values
    ),
    query<{ count: string }>(
      `SELECT COUNT(*) FROM restaurants WHERE ${where}`,
      values.slice(0, -2)
    ),
  ]);

  return {
    restaurants: dataResult.rows,
    total: parseInt(countResult.rows[0].count, 10),
  };
}

export async function getRestaurantById(id: string): Promise<Restaurant | null> {
  const result = await query<Restaurant>('SELECT * FROM restaurants WHERE id = $1', [id]);
  return result.rows[0] ?? null;
}

export async function getRestaurantByOwner(ownerId: string): Promise<Restaurant | null> {
  const result = await query<Restaurant>('SELECT * FROM restaurants WHERE owner_id = $1', [ownerId]);
  return result.rows[0] ?? null;
}

export async function updateRestaurantStatus(
  id: string,
  status: RestaurantStatus
): Promise<Restaurant | null> {
  const result = await query<Restaurant>(
    `UPDATE restaurants SET status = $1, updated_at = NOW() WHERE id = $2 RETURNING *`,
    [status, id]
  );
  return result.rows[0] ?? null;
}

export async function suspendRestaurant(id: string): Promise<void> {
  await withTransaction(async (client) => {
    await client.query(
      `UPDATE restaurants SET status = 'suspended', updated_at = NOW() WHERE id = $1`,
      [id]
    );
    // Cancel active orders from this restaurant
    await client.query(
      `UPDATE orders SET status = 'cancelled', updated_at = NOW()
       WHERE restaurant_id = $1 AND status NOT IN ('delivered', 'cancelled', 'payment_failed')`,
      [id]
    );
  });
}
