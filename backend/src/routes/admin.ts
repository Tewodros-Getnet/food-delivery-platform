import { Router, Request, Response, NextFunction } from 'express';
import { authenticate } from '../middleware/auth';
import { authorize } from '../middleware/rbac';
import { query } from '../config/database';
import { successResponse } from '../utils/response';

const router = Router();

const adminAuth = [authenticate, authorize('admin')];

// GET /admin/restaurants
router.get('/restaurants', ...adminAuth, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { status } = req.query as { status?: string };
    const conditions = status ? 'WHERE r.status = $1' : '';
    const values = status ? [status] : [];

    const result = await query(
      `SELECT r.*, u.email as owner_email, u.display_name as owner_name,
              (SELECT COUNT(*) FROM menu_items WHERE restaurant_id = r.id) as menu_count
       FROM restaurants r JOIN users u ON u.id = r.owner_id
       ${conditions} ORDER BY r.created_at DESC`,
      values
    );
    res.json(successResponse(result.rows));
  } catch (err) { next(err); }
});

// GET /admin/users
router.get('/users', ...adminAuth, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { search, role, page, limit } = req.query as Record<string, string>;
    const pageNum = parseInt(page ?? '1', 10);
    const limitNum = parseInt(limit ?? '20', 10);
    const offset = (pageNum - 1) * limitNum;

    const conditions: string[] = [];
    const values: unknown[] = [];
    let idx = 1;

    if (search) { conditions.push(`(email ILIKE $${idx} OR display_name ILIKE $${idx})`); values.push(`%${search}%`); idx++; }
    if (role) { conditions.push(`role = $${idx++}`); values.push(role); }

    const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
    values.push(limitNum, offset);

    const result = await query(
      `SELECT id, email, role, display_name, phone, status, created_at,
              (SELECT COUNT(*) FROM orders WHERE customer_id = users.id) as order_count
       FROM users ${where}
       ORDER BY created_at DESC LIMIT $${idx} OFFSET $${idx + 1}`,
      values
    );
    res.json(successResponse(result.rows));
  } catch (err) { next(err); }
});

// PUT /admin/users/:id/suspend
router.put('/users/:id/suspend', ...adminAuth, async (req: Request, res: Response, next: NextFunction) => {
  try {
    await query('UPDATE users SET status = $1, updated_at = NOW() WHERE id = $2', ['suspended', req.params.id]);
    await query('DELETE FROM refresh_tokens WHERE user_id = $1', [req.params.id]);
    res.json(successResponse({ message: 'User suspended' }));
  } catch (err) { next(err); }
});

// PUT /admin/users/:id/reactivate
router.put('/users/:id/reactivate', ...adminAuth, async (req: Request, res: Response, next: NextFunction) => {
  try {
    await query('UPDATE users SET status = $1, updated_at = NOW() WHERE id = $2', ['active', req.params.id]);
    res.json(successResponse({ message: 'User reactivated' }));
  } catch (err) { next(err); }
});

// GET /admin/analytics
router.get('/analytics', ...adminAuth, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { startDate, endDate } = req.query as { startDate?: string; endDate?: string };
    const start = startDate ?? new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
    const end = endDate ?? new Date().toISOString();

    const [totals, byStatus, topRestaurants, topRiders, activeUsers] = await Promise.all([
      query(
        `SELECT COUNT(*) as total_orders, COALESCE(SUM(total), 0) as total_revenue
         FROM orders WHERE created_at BETWEEN $1 AND $2 AND status NOT IN ('pending_payment','payment_failed')`,
        [start, end]
      ),
      query(
        `SELECT status, COUNT(*) as count FROM orders
         WHERE created_at BETWEEN $1 AND $2 GROUP BY status`,
        [start, end]
      ),
      query(
        `SELECT r.id, r.name, COUNT(o.id) as order_count
         FROM restaurants r JOIN orders o ON o.restaurant_id = r.id
         WHERE o.created_at BETWEEN $1 AND $2
         GROUP BY r.id, r.name ORDER BY order_count DESC LIMIT 10`,
        [start, end]
      ),
      query(
        `SELECT u.id, u.display_name, COUNT(o.id) as delivery_count
         FROM users u JOIN orders o ON o.rider_id = u.id
         WHERE o.status = 'delivered' AND o.created_at BETWEEN $1 AND $2
         GROUP BY u.id, u.display_name ORDER BY delivery_count DESC LIMIT 10`,
        [start, end]
      ),
      query(
        `SELECT COUNT(DISTINCT customer_id) as active_customers FROM orders
         WHERE created_at BETWEEN $1 AND $2`,
        [start, end]
      ),
    ]);

    res.json(successResponse({
      totalOrders: parseInt(totals.rows[0].total_orders as string, 10),
      totalRevenue: parseFloat(totals.rows[0].total_revenue as string),
      activeUsers: parseInt(activeUsers.rows[0].active_customers as string, 10),
      ordersByStatus: byStatus.rows,
      topRestaurants: topRestaurants.rows,
      topRiders: topRiders.rows,
      dateRange: { start, end },
    }));
  } catch (err) { next(err); }
});

export default router;
