import { query, withTransaction } from '../config/database';

export interface RatingInput {
  orderId: string;
  customerId: string;
  restaurantRating?: number;
  riderRating?: number;
  review?: string;
}

export async function submitRating(input: RatingInput): Promise<void> {
  return withTransaction(async (client) => {
    const orderResult = await client.query(
      'SELECT * FROM orders WHERE id = $1 AND customer_id = $2',
      [input.orderId, input.customerId]
    );
    const order = orderResult.rows[0] as { status: string; restaurant_id: string; rider_id: string } | undefined;

    if (!order) {
      const err = new Error('Order not found') as Error & { statusCode: number };
      err.statusCode = 404;
      throw err;
    }
    if (order.status !== 'delivered') {
      const err = new Error('Can only rate delivered orders') as Error & { statusCode: number };
      err.statusCode = 409;
      throw err;
    }

    if (input.restaurantRating !== undefined) {
      await client.query(
        `INSERT INTO ratings (order_id, customer_id, restaurant_id, rating, review)
         VALUES ($1, $2, $3, $4, $5)`,
        [input.orderId, input.customerId, order.restaurant_id, input.restaurantRating, input.review ?? null]
      );
      // Recalculate average
      await client.query(
        `UPDATE restaurants SET average_rating = (
           SELECT AVG(rating) FROM ratings WHERE restaurant_id = $1
         ) WHERE id = $1`,
        [order.restaurant_id]
      );
    }

    if (input.riderRating !== undefined && order.rider_id) {
      await client.query(
        `INSERT INTO ratings (order_id, customer_id, rider_id, rating, review)
         VALUES ($1, $2, $3, $4, $5)`,
        [input.orderId, input.customerId, order.rider_id, input.riderRating, input.review ?? null]
      );
    }
  });
}

export async function getRestaurantRatings(restaurantId: string, page = 1, limit = 20) {
  const offset = (page - 1) * limit;
  const result = await query(
    `SELECT r.*, u.display_name as customer_name FROM ratings r
     JOIN users u ON u.id = r.customer_id
     WHERE r.restaurant_id = $1
     ORDER BY r.created_at DESC LIMIT $2 OFFSET $3`,
    [restaurantId, limit, offset]
  );
  return result.rows;
}

export async function getRiderRatings(riderId: string, page = 1, limit = 20) {
  const offset = (page - 1) * limit;
  const result = await query(
    `SELECT r.*, u.display_name as customer_name FROM ratings r
     JOIN users u ON u.id = r.customer_id
     WHERE r.rider_id = $1
     ORDER BY r.created_at DESC LIMIT $2 OFFSET $3`,
    [riderId, limit, offset]
  );
  return result.rows;
}
