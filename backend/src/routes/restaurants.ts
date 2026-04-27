import { Router } from 'express';
import { authenticate } from '../middleware/auth';
import { authorize } from '../middleware/rbac';
import { Request, Response, NextFunction } from 'express';
import { getRiderRatings } from '../services/rating.service';
import { successResponse } from '../utils/response';
import {
  createRestaurantHandler, createValidation,
  listRestaurantsHandler,
  getRestaurantHandler,
  approveRestaurantHandler,
  rejectRestaurantHandler,
  suspendRestaurantHandler,
} from '../controllers/restaurant.controller';
import { getRestaurantRatings } from '../services/rating.service';

const router = Router();

router.get('/my', authenticate, authorize('restaurant'), async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { getRestaurantByOwner } = await import('../services/restaurant.service');
    const restaurant = await getRestaurantByOwner(req.userId!);
    if (!restaurant) { res.status(404).json({ success: false, data: null, error: 'Restaurant not found' }); return; }
    res.json(successResponse(restaurant));
  } catch (err) { next(err); }
});

// PUT /restaurants/my/status — toggle is_open
router.put('/my/status', authenticate, authorize('restaurant'), async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { is_open } = req.body as { is_open: boolean };
    if (typeof is_open !== 'boolean') {
      res.status(422).json({ success: false, data: null, error: 'is_open must be a boolean' });
      return;
    }
    const { getRestaurantByOwner } = await import('../services/restaurant.service');
    const restaurant = await getRestaurantByOwner(req.userId!);
    if (!restaurant) { res.status(404).json({ success: false, data: null, error: 'Restaurant not found' }); return; }
    const { query } = await import('../config/database');
    const result = await query(
      'UPDATE restaurants SET is_open = $1, updated_at = NOW() WHERE id = $2 RETURNING *',
      [is_open, restaurant.id]
    );
    res.json(successResponse(result.rows[0]));
  } catch (err) { next(err); }
});

// GET /restaurants/my/riders — list riders assigned to this restaurant
router.get('/my/riders', authenticate, authorize('restaurant'), async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { getRestaurantByOwner } = await import('../services/restaurant.service');
    const restaurant = await getRestaurantByOwner(req.userId!);
    if (!restaurant) { res.status(404).json({ success: false, data: null, error: 'Restaurant not found' }); return; }
    const { query } = await import('../config/database');
    const result = await query(
      `SELECT u.id, u.email, u.display_name, u.phone, u.status,
              rr.joined_at,
              (SELECT rl.availability FROM rider_locations rl
               WHERE rl.rider_id = u.id ORDER BY rl.timestamp DESC LIMIT 1) as availability
       FROM restaurant_riders rr
       JOIN users u ON u.id = rr.rider_id
       WHERE rr.restaurant_id = $1
       ORDER BY rr.joined_at DESC`,
      [restaurant.id]
    );
    res.json(successResponse(result.rows));
  } catch (err) { next(err); }
});

// POST /restaurants/my/riders/invite — invite a rider by email
router.post('/my/riders/invite', authenticate, authorize('restaurant'), async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { email } = req.body as { email: string };
    if (!email) { res.status(422).json({ success: false, data: null, error: 'email is required' }); return; }
    const { getRestaurantByOwner } = await import('../services/restaurant.service');
    const restaurant = await getRestaurantByOwner(req.userId!);
    if (!restaurant) { res.status(404).json({ success: false, data: null, error: 'Restaurant not found' }); return; }
    const { query } = await import('../config/database');

    // Check rider exists and has role 'rider'
    const riderResult = await query<{ id: string }>(
      `SELECT id FROM users WHERE email = $1 AND role = 'rider'`, [email]
    );
    if (!riderResult.rows[0]) {
      res.status(404).json({ success: false, data: null, error: 'No rider account found with that email' });
      return;
    }

    // Check rider is not already assigned to another restaurant
    const existing = await query(
      'SELECT restaurant_id FROM restaurant_riders WHERE rider_id = $1',
      [riderResult.rows[0].id]
    );
    if (existing.rows[0]) {
      res.status(409).json({ success: false, data: null, error: 'This rider is already assigned to another restaurant' });
      return;
    }

    // Upsert invitation
    await query(
      `INSERT INTO rider_invitations (restaurant_id, rider_email)
       VALUES ($1, $2)
       ON CONFLICT (restaurant_id, rider_email) DO UPDATE SET status = 'pending', created_at = NOW()`,
      [restaurant.id, email]
    );
    res.json(successResponse({ message: 'Invitation sent' }));
  } catch (err) { next(err); }
});

// DELETE /restaurants/my/riders/:riderId — remove a rider from the team
router.delete('/my/riders/:riderId', authenticate, authorize('restaurant'), async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { getRestaurantByOwner } = await import('../services/restaurant.service');
    const restaurant = await getRestaurantByOwner(req.userId!);
    if (!restaurant) { res.status(404).json({ success: false, data: null, error: 'Restaurant not found' }); return; }
    const { query } = await import('../config/database');
    await query(
      'DELETE FROM restaurant_riders WHERE rider_id = $1 AND restaurant_id = $2',
      [req.params.riderId, restaurant.id]
    );
    res.json(successResponse({ message: 'Rider removed from team' }));
  } catch (err) { next(err); }
});

// PUT /restaurants/my/hours — set weekly operating hours
router.put('/my/hours', authenticate, authorize('restaurant'), async (req: Request, res: Response, next: NextFunction) => {
  try {
    const hours = req.body as Record<string, unknown>;
    const DAYS = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
    const TIME_RE = /^([01]\d|2[0-3]):[0-5]\d$/;

    for (const [day, schedule] of Object.entries(hours)) {
      if (!DAYS.includes(day)) {
        res.status(422).json({ success: false, data: null, error: `Invalid day: ${day}` });
        return;
      }
      const s = schedule as Record<string, unknown>;
      if (s.closed === true) continue;
      if (typeof s.open !== 'string' || !TIME_RE.test(s.open) ||
          typeof s.close !== 'string' || !TIME_RE.test(s.close)) {
        res.status(422).json({
          success: false, data: null,
          error: `Invalid time format for ${day}. Use HH:MM (24-hour).`,
        });
        return;
      }
    }

    const { updateOperatingHours } = await import('../services/restaurant.service');
    const updated = await updateOperatingHours(req.userId!, hours as import('../services/restaurant.service').OperatingHours);
    if (!updated) { res.status(404).json({ success: false, data: null, error: 'Restaurant not found' }); return; }
    res.json(successResponse(updated));
  } catch (err) { next(err); }
});

// GET /restaurants/my/analytics — restaurant owner's own analytics
router.get('/my/analytics', authenticate, authorize('restaurant'), async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { getRestaurantByOwner } = await import('../services/restaurant.service');
    const restaurant = await getRestaurantByOwner(req.userId!);
    if (!restaurant) { res.status(404).json({ success: false, data: null, error: 'Restaurant not found' }); return; }

    const { query } = await import('../config/database');
    const restaurantId = restaurant.id;

    const now = new Date();
    const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).toISOString();
    const weekStart = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000).toISOString();
    const monthStart = new Date(now.getTime() - 30 * 24 * 60 * 60 * 1000).toISOString();

    const [todayStats, weekStats, monthStats, topItems, ordersByStatus, recentOrders, avgPrepTime] = await Promise.all([
      // Today's orders and revenue
      query(
        `SELECT COUNT(*) as orders, COALESCE(SUM(total), 0) as revenue
         FROM orders WHERE restaurant_id = $1 AND created_at >= $2
         AND status NOT IN ('pending_payment', 'payment_failed', 'cancelled')`,
        [restaurantId, todayStart]
      ),
      // This week
      query(
        `SELECT COUNT(*) as orders, COALESCE(SUM(total), 0) as revenue
         FROM orders WHERE restaurant_id = $1 AND created_at >= $2
         AND status NOT IN ('pending_payment', 'payment_failed', 'cancelled')`,
        [restaurantId, weekStart]
      ),
      // This month
      query(
        `SELECT COUNT(*) as orders, COALESCE(SUM(total), 0) as revenue
         FROM orders WHERE restaurant_id = $1 AND created_at >= $2
         AND status NOT IN ('pending_payment', 'payment_failed', 'cancelled')`,
        [restaurantId, monthStart]
      ),
      // Top 5 menu items by order count (last 30 days)
      query(
        `SELECT oi.item_name, SUM(oi.quantity) as total_quantity, COUNT(DISTINCT oi.order_id) as order_count
         FROM order_items oi
         JOIN orders o ON o.id = oi.order_id
         WHERE o.restaurant_id = $1 AND o.created_at >= $2
           AND o.status NOT IN ('pending_payment', 'payment_failed', 'cancelled')
         GROUP BY oi.item_name
         ORDER BY total_quantity DESC LIMIT 5`,
        [restaurantId, monthStart]
      ),
      // Orders by status (last 30 days)
      query(
        `SELECT status, COUNT(*) as count FROM orders
         WHERE restaurant_id = $1 AND created_at >= $2
         GROUP BY status ORDER BY count DESC`,
        [restaurantId, monthStart]
      ),
      // Last 10 orders
      query(
        `SELECT o.id, o.status, o.total, o.created_at,
                (SELECT STRING_AGG(oi.item_name || ' x' || oi.quantity, ', ' ORDER BY oi.id)
                 FROM order_items oi WHERE oi.order_id = o.id) as items_summary
         FROM orders o
         WHERE o.restaurant_id = $1
         ORDER BY o.created_at DESC LIMIT 10`,
        [restaurantId]
      ),
      // Average prep time for delivered orders (last 30 days)
      query(
        `SELECT AVG(estimated_prep_time_minutes) as avg_prep_minutes
         FROM orders WHERE restaurant_id = $1 AND created_at >= $2
           AND status = 'delivered' AND estimated_prep_time_minutes IS NOT NULL`,
        [restaurantId, monthStart]
      ),
    ]);

    res.json(successResponse({
      today: {
        orders: parseInt(todayStats.rows[0].orders as string, 10),
        revenue: parseFloat(todayStats.rows[0].revenue as string),
      },
      week: {
        orders: parseInt(weekStats.rows[0].orders as string, 10),
        revenue: parseFloat(weekStats.rows[0].revenue as string),
      },
      month: {
        orders: parseInt(monthStats.rows[0].orders as string, 10),
        revenue: parseFloat(monthStats.rows[0].revenue as string),
      },
      topItems: topItems.rows,
      ordersByStatus: ordersByStatus.rows,
      recentOrders: recentOrders.rows,
      avgPrepTimeMinutes: avgPrepTime.rows[0]?.avg_prep_minutes
        ? parseFloat(avgPrepTime.rows[0].avg_prep_minutes as string)
        : null,
      restaurantRating: restaurant.average_rating,
    }));
  } catch (err) { next(err); }
});
router.get('/', listRestaurantsHandler);
router.get('/:id', getRestaurantHandler);
router.get('/:id/ratings', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const ratings = await getRestaurantRatings(req.params.id);
    res.json(successResponse(ratings));
  } catch (err) { next(err); }
});

// POST /restaurants/ratings/:ratingId/reply — restaurant owner replies to a review
router.post('/ratings/:ratingId/reply', authenticate, authorize('restaurant'), async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { reply } = req.body as { reply?: string };
    if (!reply || !reply.trim()) {
      res.status(422).json({ success: false, data: null, error: 'Reply text is required' });
      return;
    }
    const { replyToRating } = await import('../services/rating.service');
    await replyToRating(req.params.ratingId, req.userId!, reply.trim());
    res.json(successResponse({ message: 'Reply posted' }));
  } catch (err) { next(err); }
});

// PUT /restaurants/my/banner — set or clear promotional banner
router.put('/my/banner', authenticate, authorize('restaurant'), async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { text, imageBase64 } = req.body as { text?: string; imageBase64?: string };
    const { getRestaurantByOwner } = await import('../services/restaurant.service');
    const restaurant = await getRestaurantByOwner(req.userId!);
    if (!restaurant) { res.status(404).json({ success: false, data: null, error: 'Restaurant not found' }); return; }

    const { query: dbQuery } = await import('../config/database');
    let imageUrl: string | null = restaurant.promo_banner_image_url ?? null;

    if (imageBase64) {
      const { uploadImage } = await import('../services/cloudinary.service');
      imageUrl = await uploadImage(imageBase64, 'restaurants/banners');
    }

    const result = await dbQuery(
      `UPDATE restaurants
       SET promo_banner_text = $1, promo_banner_image_url = $2, updated_at = NOW()
       WHERE id = $3 RETURNING *`,
      [text?.trim() ?? null, imageUrl, restaurant.id]
    );
    res.json(successResponse(result.rows[0]));
  } catch (err) { next(err); }
});
router.post('/', authenticate, authorize('restaurant'), createValidation, createRestaurantHandler);
router.post('/:id/approve', authenticate, authorize('admin'), approveRestaurantHandler);
router.post('/:id/reject', authenticate, authorize('admin'), rejectRestaurantHandler);
router.put('/:id/suspend', authenticate, authorize('admin'), suspendRestaurantHandler);

export default router;
