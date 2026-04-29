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

// GET /admin/users — Fix 1: correct LIMIT/OFFSET parameterization + Fix 5: pagination metadata
router.get('/users', ...adminAuth, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { search, role, page, limit } = req.query as Record<string, string>;
    const pageNum = parseInt(page ?? '1', 10);
    const limitNum = Math.min(parseInt(limit ?? '20', 10), 100);
    const offset = (pageNum - 1) * limitNum;

    const conditions: string[] = [];
    const values: unknown[] = [];
    let idx = 1;

    if (search) {
      conditions.push('(email ILIKE $' + idx + ' OR display_name ILIKE $' + idx + ')');
      values.push(`%${search}%`);
      idx++;
    }
    if (role) {
      conditions.push('role = $' + idx);
      values.push(role);
      idx++;
    }

    const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';

    // Count total for pagination
    const countResult = await query(
      `SELECT COUNT(*) as total FROM users ${where}`,
      values.slice()
    );
    const total = parseInt(countResult.rows[0].total as string, 10);

    values.push(limitNum, offset);
    const limitParam = '$' + idx;
    const offsetParam = '$' + (idx + 1);

    const result = await query(
      `SELECT id, email, role, display_name, phone, status, email_verified, created_at,
              CASE
                WHEN role = 'customer' THEN (SELECT COUNT(*) FROM orders WHERE customer_id = users.id)::text
                WHEN role = 'rider'    THEN (SELECT COUNT(*) FROM orders WHERE rider_id = users.id AND status = 'delivered')::text
                WHEN role = 'restaurant' THEN (SELECT COUNT(*) FROM restaurants WHERE owner_id = users.id)::text
                ELSE '—'
              END as order_count
       FROM users ${where}
       ORDER BY created_at DESC LIMIT ${limitParam} OFFSET ${offsetParam}`,
      values
    );

    res.json(successResponse({
      users: result.rows,
      pagination: { page: pageNum, limit: limitNum, total, pages: Math.ceil(total / limitNum) },
    }));
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

// GET /admin/orders — Fix 4: refund_failed filter + Fix 5: pagination metadata
router.get('/orders', ...adminAuth, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { status, payment_status, page, limit } = req.query as Record<string, string>;
    const pageNum = parseInt(page ?? '1', 10);
    const limitNum = Math.min(parseInt(limit ?? '30', 10), 100);
    const offset = (pageNum - 1) * limitNum;

    const conditions: string[] = [];
    const values: unknown[] = [];
    let idx = 1;

    if (status) {
      conditions.push('o.status = $' + idx);
      values.push(status);
      idx++;
    }
    if (payment_status) {
      conditions.push('o.payment_status = $' + idx);
      values.push(payment_status);
      idx++;
    }

    const where = conditions.length ? 'WHERE ' + conditions.join(' AND ') : '';

    const countResult = await query(
      `SELECT COUNT(*) as total FROM orders o ${where}`,
      values.slice()
    );
    const total = parseInt(countResult.rows[0].total as string, 10);

    values.push(limitNum, offset);
    const limitParam = '$' + idx;
    const offsetParam = '$' + (idx + 1);

    const result = await query(
      `SELECT o.id, o.status, o.total, o.payment_status, o.cancellation_reason, o.cancelled_by,
              o.created_at, o.updated_at,
              cu.email as customer_email, cu.display_name as customer_name,
              r.name as restaurant_name,
              ru.display_name as rider_name, ru.email as rider_email
       FROM orders o
       JOIN users cu ON cu.id = o.customer_id
       JOIN restaurants r ON r.id = o.restaurant_id
       LEFT JOIN users ru ON ru.id = o.rider_id
       ${where}
       ORDER BY o.created_at DESC
       LIMIT ${limitParam} OFFSET ${offsetParam}`,
      values
    );

    res.json(successResponse({
      orders: result.rows,
      pagination: { page: pageNum, limit: limitNum, total, pages: Math.ceil(total / limitNum) },
    }));
  } catch (err) { next(err); }
});

// PUT /admin/orders/:id/cancel — force-cancel a stuck order and initiate refund
router.put('/orders/:id/cancel', ...adminAuth, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { reason } = req.body as { reason?: string };
    const orderResult = await query<{ status: string; customer_id: string; restaurant_id: string }>(
      'SELECT status, customer_id, restaurant_id FROM orders WHERE id = $1',
      [req.params.id]
    );
    if (!orderResult.rows[0]) { res.status(404).json({ success: false, data: null, error: 'Order not found' }); return; }
    const order = orderResult.rows[0];

    if (['delivered', 'cancelled'].includes(order.status)) {
      res.status(409).json({ success: false, data: null, error: 'Order is already completed or cancelled' });
      return;
    }

    await query(
      `UPDATE orders SET status = 'cancelled', cancellation_reason = $1,
       cancelled_by = 'admin', cancelled_at = NOW(), updated_at = NOW()
       WHERE id = $2`,
      [reason ?? 'Cancelled by admin', req.params.id]
    );

    const { initiateRefund } = await import('../services/refund.service');
    try { await initiateRefund(req.params.id); } catch { /* payment_status set by initiateRefund */ }

    const updatedResult = await query('SELECT * FROM orders WHERE id = $1', [req.params.id]);
    const updated = updatedResult.rows[0] as import('../models/order.model').Order | undefined;
    if (updated) {
      const { emitOrderStatusChanged, emitToRestaurant } = await import('../services/socket.service');
      emitOrderStatusChanged(updated, order.customer_id);
      const rResult = await query<{ owner_id: string }>('SELECT owner_id FROM restaurants WHERE id = $1', [order.restaurant_id]);
      if (rResult.rows[0]) emitToRestaurant(rResult.rows[0].owner_id, updated);
    }

    res.json(successResponse({ message: 'Order cancelled and refund initiated' }));
  } catch (err) { next(err); }
});

// PUT /admin/orders/:id/reassign-rider
router.put('/orders/:id/reassign-rider', ...adminAuth, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const orderResult = await query<{ status: string; restaurant_id: string; rider_id: string | null }>(
      'SELECT status, restaurant_id, rider_id FROM orders WHERE id = $1',
      [req.params.id]
    );
    if (!orderResult.rows[0]) { res.status(404).json({ success: false, data: null, error: 'Order not found' }); return; }
    const order = orderResult.rows[0];

    if (!['ready_for_pickup', 'rider_assigned'].includes(order.status)) {
      res.status(409).json({ success: false, data: null, error: 'Order must be ready_for_pickup or rider_assigned to reassign' });
      return;
    }

    if (order.rider_id) {
      const { setRiderAvailability } = await import('../services/rider.service');
      await setRiderAvailability(order.rider_id, 'available');
    }

    await query(
      `UPDATE orders SET status = 'ready_for_pickup', rider_id = NULL, updated_at = NOW() WHERE id = $1`,
      [req.params.id]
    );

    const { startDispatch, cancelRetrySession } = await import('../services/rider.service');
    cancelRetrySession(req.params.id);
    void startDispatch(req.params.id, order.restaurant_id);

    res.json(successResponse({ message: 'Rider reassignment started' }));
  } catch (err) { next(err); }
});

// PUT /admin/restaurants/:id/unsuspend — Fix 2: reactivate suspended restaurants
router.put('/restaurants/:id/unsuspend', ...adminAuth, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const result = await query(
      `UPDATE restaurants SET status = 'approved', updated_at = NOW() WHERE id = $1 RETURNING *`,
      [req.params.id]
    );
    if (!result.rows[0]) { res.status(404).json({ success: false, data: null, error: 'Restaurant not found' }); return; }
    res.json(successResponse(result.rows[0]));
  } catch (err) { next(err); }
});

// ── Platform Config (Medium #7) ───────────────────────────────────────────────

// GET /admin/config
router.get('/config', ...adminAuth, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const result = await query('SELECT key, value, updated_at FROM platform_config ORDER BY key');
    res.json(successResponse(result.rows));
  } catch (err) { next(err); }
});

// PUT /admin/config/:key
router.put('/config/:key', ...adminAuth, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { value } = req.body as { value: string };
    if (value === undefined || value === null) {
      res.status(422).json({ success: false, data: null, error: 'value is required' });
      return;
    }
    const result = await query(
      `INSERT INTO platform_config (key, value, updated_at)
       VALUES ($1, $2, NOW())
       ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW()
       RETURNING *`,
      [req.params.key, String(value)]
    );
    res.json(successResponse(result.rows[0]));
  } catch (err) { next(err); }
});

// ── Riders (Medium #8) ────────────────────────────────────────────────────────

// GET /admin/riders
router.get('/riders', ...adminAuth, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { page, limit } = req.query as Record<string, string>;
    const pageNum = parseInt(page ?? '1', 10);
    const limitNum = Math.min(parseInt(limit ?? '20', 10), 100);
    const offset = (pageNum - 1) * limitNum;

    const countResult = await query(
      `SELECT COUNT(*) as total FROM users WHERE role = 'rider'`
    );
    const total = parseInt(countResult.rows[0].total as string, 10);

    const result = await query(
      `SELECT u.id, u.email, u.display_name, u.phone, u.status, u.created_at,
              rl.availability, rl.timestamp as last_seen,
              rr.restaurant_id,
              r.name as restaurant_name,
              (SELECT COUNT(*) FROM orders WHERE rider_id = u.id AND status = 'delivered') as total_deliveries,
              (SELECT AVG(rating) FROM ratings WHERE rider_id = u.id) as average_rating
       FROM users u
       LEFT JOIN rider_locations rl ON rl.rider_id = u.id
       LEFT JOIN restaurant_riders rr ON rr.rider_id = u.id
       LEFT JOIN restaurants r ON r.id = rr.restaurant_id
       WHERE u.role = 'rider'
       ORDER BY u.created_at DESC
       LIMIT $1 OFFSET $2`,
      [limitNum, offset]
    );

    res.json(successResponse({
      riders: result.rows,
      pagination: { page: pageNum, limit: limitNum, total, pages: Math.ceil(total / limitNum) },
    }));
  } catch (err) { next(err); }
});

// GET /admin/analytics — Fix 3: date range picker support (already had it, now documented)
router.get('/analytics', ...adminAuth, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { startDate, endDate } = req.query as { startDate?: string; endDate?: string };
    const start = startDate ?? new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
    const end = endDate ?? new Date().toISOString();

    const [totals, byStatus, topRestaurants, topRiders, activeUsers, refundFailed] = await Promise.all([
      query(
        `SELECT COUNT(*) as total_orders, COALESCE(SUM(total), 0) as total_revenue
         FROM orders WHERE created_at BETWEEN $1 AND $2 AND status NOT IN ('pending_payment','payment_failed')`,
        [start, end]
      ),
      query(
        `SELECT status, COUNT(*) as count FROM orders WHERE created_at BETWEEN $1 AND $2 GROUP BY status`,
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
        `SELECT COUNT(DISTINCT customer_id) as active_customers FROM orders WHERE created_at BETWEEN $1 AND $2`,
        [start, end]
      ),
      // Fix 4: count refund_failed orders for the dashboard alert
      query(
        `SELECT COUNT(*) as count FROM orders WHERE payment_status = 'refund_failed'`,
        []
      ),
    ]);

    res.json(successResponse({
      totalOrders: parseInt(totals.rows[0].total_orders as string, 10),
      totalRevenue: parseFloat(totals.rows[0].total_revenue as string),
      activeUsers: parseInt(activeUsers.rows[0].active_customers as string, 10),
      refundFailedCount: parseInt(refundFailed.rows[0].count as string, 10),
      ordersByStatus: byStatus.rows,
      topRestaurants: topRestaurants.rows,
      topRiders: topRiders.rows,
      dateRange: { start, end },
    }));
  } catch (err) { next(err); }
});

export default router;
