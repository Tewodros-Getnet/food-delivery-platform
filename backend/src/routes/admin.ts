import { Router, Request, Response, NextFunction } from 'express';
import { authenticate } from '../middleware/auth';
import { authorize } from '../middleware/rbac';
import { query } from '../config/database';
import { successResponse } from '../utils/response';
import { resendOtpInternal } from '../services/auth.service';

const router = Router();

const adminAuth = [authenticate, authorize('admin')];

// GET /admin/restaurants
router.get('/restaurants', ...adminAuth, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { status, search } = req.query as { status?: string; search?: string };
    const conditions: string[] = [];
    const values: unknown[] = [];
    let idx = 1;

    if (status) {
      conditions.push(`r.status = $${idx++}`);
      values.push(status);
    }
    if (search) {
      conditions.push(`(r.name ILIKE $${idx} OR u.email ILIKE $${idx} OR u.display_name ILIKE $${idx})`);
      values.push(`%${search}%`);
      idx++;
    }

    const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';

    const result = await query(
      `SELECT r.id, r.name, r.description, r.address, r.category, r.status,
              r.average_rating, r.is_open, r.logo_url, r.cover_image_url,
              r.latitude, r.longitude, r.operating_hours, r.created_at, r.updated_at,
              r.rejection_reason,
              u.email as owner_email, u.display_name as owner_name, u.phone as owner_phone,
              (SELECT COUNT(*) FROM menu_items WHERE restaurant_id = r.id) as menu_count,
              (SELECT COUNT(*) FROM orders
               WHERE restaurant_id = r.id
               AND status NOT IN ('delivered','cancelled','payment_failed')) as active_orders_count
       FROM restaurants r JOIN users u ON u.id = r.owner_id
       ${where} ORDER BY r.created_at DESC`,
      values
    );
    res.json(successResponse(result.rows));
  } catch (err) { next(err); }
});

// GET /admin/restaurants/:id — full detail
router.get('/restaurants/:id', ...adminAuth, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const result = await query(
      `SELECT r.*, u.email as owner_email, u.display_name as owner_name, u.phone as owner_phone,
              (SELECT COUNT(*) FROM menu_items WHERE restaurant_id = r.id) as menu_count,
              (SELECT COUNT(*) FROM orders
               WHERE restaurant_id = r.id
               AND status NOT IN ('delivered','cancelled','payment_failed')) as active_orders_count,
              (SELECT COUNT(*) FROM orders WHERE restaurant_id = r.id AND status = 'delivered') as total_orders
       FROM restaurants r JOIN users u ON u.id = r.owner_id
       WHERE r.id = $1`,
      [req.params.id]
    );
    if (!result.rows[0]) { res.status(404).json({ success: false, data: null, error: 'Restaurant not found' }); return; }
    res.json(successResponse(result.rows[0]));
  } catch (err) { next(err); }
});

// GET /admin/restaurants/:id/menu — paginated menu items
router.get('/restaurants/:id/menu', ...adminAuth, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const result = await query(
      `SELECT id, name, description, price, category, is_available, image_url, created_at
       FROM menu_items WHERE restaurant_id = $1 ORDER BY category, name`,
      [req.params.id]
    );
    res.json(successResponse(result.rows));
  } catch (err) { next(err); }
});

// GET /admin/restaurants/:id/active-orders — in-progress orders
router.get('/restaurants/:id/active-orders', ...adminAuth, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const result = await query(
      `SELECT o.id, o.status, o.total, o.created_at,
              u.email as customer_email, u.display_name as customer_name,
              ru.display_name as rider_name,
              (SELECT STRING_AGG(oi.item_name || ' x' || oi.quantity, ', ' ORDER BY oi.id)
               FROM order_items oi WHERE oi.order_id = o.id) as items_summary
       FROM orders o
       JOIN users u ON u.id = o.customer_id
       LEFT JOIN users ru ON ru.id = o.rider_id
       WHERE o.restaurant_id = $1
         AND o.status NOT IN ('delivered','cancelled','payment_failed')
       ORDER BY o.created_at DESC`,
      [req.params.id]
    );
    res.json(successResponse(result.rows));
  } catch (err) { next(err); }
});

// GET /admin/users
router.get('/users', ...adminAuth, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { search, role, status, verified, page, limit } = req.query as Record<string, string>;
    const pageNum  = parseInt(page  ?? '1',  10);
    const limitNum = Math.min(parseInt(limit ?? '20', 10), 100);
    const offset   = (pageNum - 1) * limitNum;

    const conditions: string[] = [];
    const values: unknown[]    = [];
    let idx = 1;

    if (search) {
      conditions.push(`(email ILIKE $${idx} OR display_name ILIKE $${idx} OR phone ILIKE $${idx})`);
      values.push(`%${search}%`);
      idx++;
    }
    if (role) {
      conditions.push(`role = $${idx++}`);
      values.push(role);
    }
    // status filter: 'active' | 'suspended'
    if (status) {
      conditions.push(`status = $${idx++}`);
      values.push(status);
    }
    // verified filter: 'true' | 'false'
    if (verified === 'true' || verified === 'false') {
      conditions.push(`email_verified = $${idx++}`);
      values.push(verified === 'true');
    }

    const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';

    const countResult = await query(
      `SELECT COUNT(*) as total FROM users ${where}`,
      values.slice(),
    );
    const total = parseInt(countResult.rows[0].total as string, 10);

    // Also count unverified active users so the UI can show an alert banner
    const unverifiedResult = await query(
      `SELECT COUNT(*) as total FROM users WHERE email_verified = false AND status = 'active'`,
      [],
    );
    const unverifiedCount = parseInt(unverifiedResult.rows[0].total as string, 10);

    values.push(limitNum, offset);
    const limitParam  = `$${idx}`;
    const offsetParam = `$${idx + 1}`;

    const result = await query(
      `SELECT id, email, role, display_name, phone, status, email_verified,
              profile_photo_url, created_at, updated_at,
              CASE
                WHEN role = 'customer'    THEN (SELECT COUNT(*) FROM orders      WHERE customer_id = users.id)::text
                WHEN role = 'rider'       THEN (SELECT COUNT(*) FROM orders      WHERE rider_id    = users.id AND status = 'delivered')::text
                WHEN role = 'restaurant'  THEN (SELECT COUNT(*) FROM restaurants WHERE owner_id    = users.id)::text
                ELSE '—'
              END as order_count
       FROM users ${where}
       ORDER BY created_at DESC
       LIMIT ${limitParam} OFFSET ${offsetParam}`,
      values,
    );

    res.json(successResponse({
      users:          result.rows,
      unverifiedCount,
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

// DELETE /admin/users/:id — hard delete, removes all dependent rows first
router.delete('/users/:id', ...adminAuth, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const existing = await query('SELECT id, role FROM users WHERE id = $1', [req.params.id]);
    if (!existing.rows[0]) {
      res.status(404).json({ success: false, data: null, error: 'User not found' });
      return;
    }
    const id = req.params.id;

    // Delete child rows that reference this user, in dependency order.
    // Many tables have ON DELETE CASCADE already (refresh_tokens, fcm_tokens,
    // rider_locations, order_items via orders) — but orders, disputes, ratings,
    // addresses and restaurants do NOT, so we handle them explicitly.

    // 1. Disputes referencing orders that belong to this user (as customer or rider)
    await query(`DELETE FROM disputes WHERE order_id IN (SELECT id FROM orders WHERE customer_id = $1)`, [id]);
    await query(`DELETE FROM disputes WHERE customer_id = $1`, [id]);

    // 2. Ratings referencing orders that belong to this user
    await query(`DELETE FROM ratings WHERE order_id IN (SELECT id FROM orders WHERE customer_id = $1)`, [id]);
    await query(`DELETE FROM ratings WHERE customer_id = $1`, [id]);
    await query(`DELETE FROM ratings WHERE rider_id = $1`, [id]);

    // 3. Orders where this user is the customer (order_items cascade from orders)
    await query(`DELETE FROM orders WHERE customer_id = $1`, [id]);

    // 4. Null out rider_id on any orders where this user was the rider
    //    (rider_id is nullable, so this is safe)
    await query(`UPDATE orders SET rider_id = NULL WHERE rider_id = $1`, [id]);

    // 5. Addresses
    await query(`DELETE FROM addresses WHERE user_id = $1`, [id]);

    // 6. Restaurant owned by this user (menu_items cascade from restaurants)
    await query(`DELETE FROM restaurants WHERE owner_id = $1`, [id]);

    // 7. The user row itself — refresh_tokens, fcm_tokens, rider_locations,
    //    verification_codes, password_reset_tokens all have ON DELETE CASCADE
    //    or will be cleaned up by the FK cascade on users.id
    await query(`DELETE FROM users WHERE id = $1`, [id]);

    res.json(successResponse({ message: 'User deleted' }));
  } catch (err) { next(err); }
});

// PUT /admin/users/:id/role — change a user's role
router.put('/users/:id/role', ...adminAuth, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { role } = req.body as { role?: string };
    const valid = ['customer', 'restaurant', 'rider', 'admin'];
    if (!role || !valid.includes(role)) {
      res.status(422).json({ success: false, data: null, error: `role must be one of: ${valid.join(', ')}` });
      return;
    }
    const result = await query(
      'UPDATE users SET role = $1, updated_at = NOW() WHERE id = $2 RETURNING id, email, role',
      [role, req.params.id]
    );
    if (!result.rows[0]) {
      res.status(404).json({ success: false, data: null, error: 'User not found' });
      return;
    }
    // Invalidate existing sessions — role embedded in JWT must be refreshed
    await query('DELETE FROM refresh_tokens WHERE user_id = $1', [req.params.id]);
    res.json(successResponse(result.rows[0]));
  } catch (err) { next(err); }
});

// POST /admin/users/:id/force-logout — invalidate all active sessions
router.post('/users/:id/force-logout', ...adminAuth, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const result = await query(
      'DELETE FROM refresh_tokens WHERE user_id = $1 RETURNING id',
      [req.params.id]
    );
    res.json(successResponse({
      message: 'User sessions terminated',
      sessionsRevoked: result.rowCount ?? 0,
    }));
  } catch (err) { next(err); }
});

// POST /admin/users/:id/resend-verification — re-send OTP for unverified accounts
router.post('/users/:id/resend-verification', ...adminAuth, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const userResult = await query<{ email: string; email_verified: boolean }>(
      'SELECT email, email_verified FROM users WHERE id = $1',
      [req.params.id]
    );
    const user = userResult.rows[0];
    if (!user) {
      res.status(404).json({ success: false, data: null, error: 'User not found' });
      return;
    }
    if (user.email_verified) {
      res.status(400).json({ success: false, data: null, error: 'Email already verified' });
      return;
    }
    await resendOtpInternal(req.params.id);
    res.json(successResponse({ message: 'Verification email sent' }));
  } catch (err) { next(err); }
});
// GET /admin/orders — supports status, payment_status, search, startDate, endDate, page, limit
router.get('/orders', ...adminAuth, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { status, payment_status, search, startDate, endDate, page, limit } = req.query as Record<string, string>;
    const pageNum = parseInt(page ?? '1', 10);
    const limitNum = Math.min(parseInt(limit ?? '30', 10), 100);
    const offset = (pageNum - 1) * limitNum;

    const conditions: string[] = [];
    const values: unknown[] = [];
    let idx = 1;

    if (status) { conditions.push(`o.status = $${idx++}`); values.push(status); }
    if (payment_status) { conditions.push(`o.payment_status = $${idx++}`); values.push(payment_status); }
    if (startDate) { conditions.push(`o.created_at >= $${idx++}`); values.push(startDate); }
    if (endDate) { conditions.push(`o.created_at <= $${idx++}`); values.push(endDate); }
    if (search) {
      conditions.push(
        `(o.id::text ILIKE $${idx} OR cu.email ILIKE $${idx} OR cu.display_name ILIKE $${idx} OR r.name ILIKE $${idx})`
      );
      values.push(`%${search}%`);
      idx++;
    }

    const where = conditions.length ? 'WHERE ' + conditions.join(' AND ') : '';

    const countResult = await query(
      `SELECT COUNT(*) as total FROM orders o
       JOIN users cu ON cu.id = o.customer_id
       JOIN restaurants r ON r.id = o.restaurant_id
       ${where}`,
      values.slice()
    );
    const total = parseInt(countResult.rows[0].total as string, 10);

    values.push(limitNum, offset);
    const limitParam = '$' + idx;
    const offsetParam = '$' + (idx + 1);

    const result = await query(
      `SELECT o.id, o.status, o.total, o.subtotal, o.delivery_fee, o.payment_status,
              o.payment_reference, o.payment_method, o.cancellation_reason, o.cancelled_by,
              o.cancelled_at, o.created_at, o.updated_at, o.estimated_delivery_time,
              o.estimated_prep_time_minutes, o.notes,
              cu.id as customer_id, cu.email as customer_email, cu.display_name as customer_name,
              cu.phone as customer_phone,
              r.id as restaurant_id, r.name as restaurant_name,
              ru.id as rider_id, ru.display_name as rider_name, ru.email as rider_email,
              ru.phone as rider_phone,
              a.address_line as delivery_address, a.label as delivery_city
       FROM orders o
       JOIN users cu ON cu.id = o.customer_id
       JOIN restaurants r ON r.id = o.restaurant_id
       LEFT JOIN users ru ON ru.id = o.rider_id
       LEFT JOIN addresses a ON a.id = o.delivery_address_id
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

// GET /admin/orders/:id — full detail with items
router.get('/orders/:id', ...adminAuth, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const orderResult = await query(
      `SELECT o.*, 
              cu.email as customer_email, cu.display_name as customer_name, cu.phone as customer_phone,
              r.name as restaurant_name, r.address as restaurant_address,
              ru.display_name as rider_name, ru.email as rider_email, ru.phone as rider_phone,
              a.address_line as delivery_line1, a.label as delivery_line2,
              a.label as delivery_city, a.latitude as delivery_lat, a.longitude as delivery_lon,
              (SELECT id FROM disputes WHERE order_id = o.id LIMIT 1) as dispute_id
       FROM orders o
       JOIN users cu ON cu.id = o.customer_id
       JOIN restaurants r ON r.id = o.restaurant_id
       LEFT JOIN users ru ON ru.id = o.rider_id
       LEFT JOIN addresses a ON a.id = o.delivery_address_id
       WHERE o.id = $1`,
      [req.params.id]
    );
    if (!orderResult.rows[0]) {
      res.status(404).json({ success: false, data: null, error: 'Order not found' });
      return;
    }

    const itemsResult = await query(
      `SELECT oi.id, oi.item_name, oi.quantity, oi.unit_price,
              oi.item_image_url,
              COALESCE(oi.selected_modifiers, '[]'::jsonb) as selected_modifiers
       FROM order_items oi WHERE oi.order_id = $1 ORDER BY oi.id`,
      [req.params.id]
    );

    res.json(successResponse({ ...orderResult.rows[0], items: itemsResult.rows }));
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

// GET /admin/riders — paginated list with filters
router.get('/riders', ...adminAuth, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { page, limit, search, status, availability } = req.query as Record<string, string>;
    const pageNum  = parseInt(page  ?? '1',  10);
    const limitNum = Math.min(parseInt(limit ?? '20', 10), 100);
    const offset   = (pageNum - 1) * limitNum;

    const conditions: string[] = [`u.role = 'rider'`];
    const values: unknown[]    = [];
    let idx = 1;

    if (search) {
      conditions.push(`(u.email ILIKE $${idx} OR u.display_name ILIKE $${idx} OR u.phone ILIKE $${idx})`);
      values.push(`%${search}%`);
      idx++;
    }
    if (status) {
      conditions.push(`u.status = $${idx++}`);
      values.push(status);
    }
    if (availability) {
      conditions.push(`rl.availability = $${idx++}`);
      values.push(availability);
    }

    const where = conditions.join(' AND ');

    const countResult = await query(
      `SELECT COUNT(*) as total FROM users u
       LEFT JOIN rider_locations rl ON rl.rider_id = u.id
       WHERE ${where}`,
      values.slice(),
    );
    const total = parseInt(countResult.rows[0].total as string, 10);

    values.push(limitNum, offset);
    const result = await query(
      `SELECT u.id, u.email, u.display_name, u.phone, u.status, u.created_at,
              rl.availability, rl.timestamp as last_seen,
              rr.restaurant_id,
              r.name as restaurant_name,
              ri.status as invitation_status,
              rinv.name as invited_by,
              (SELECT COUNT(*) FROM orders WHERE rider_id = u.id AND status = 'delivered') as total_deliveries,
              (SELECT AVG(rating)::numeric(3,2) FROM ratings WHERE rider_id = u.id) as average_rating
       FROM users u
       LEFT JOIN rider_locations    rl   ON rl.rider_id   = u.id
       LEFT JOIN restaurant_riders  rr   ON rr.rider_id   = u.id
       LEFT JOIN restaurants        r    ON r.id           = rr.restaurant_id
       -- rider_invitations stores the rider's email, not rider_id
       LEFT JOIN rider_invitations  ri   ON ri.rider_email = u.email
       LEFT JOIN restaurants        rinv ON rinv.id        = ri.restaurant_id
       WHERE ${where}
       ORDER BY u.created_at DESC
       LIMIT $${idx} OFFSET $${idx + 1}`,
      values,
    );

    res.json(successResponse({
      riders:     result.rows,
      pagination: { page: pageNum, limit: limitNum, total, pages: Math.ceil(total / limitNum) },
    }));
  } catch (err) { next(err); }
});

// GET /admin/riders/:id — single rider detail with recent deliveries
router.get('/riders/:id', ...adminAuth, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { id } = req.params;

    const riderResult = await query(
      `SELECT u.id, u.email, u.display_name, u.phone, u.status,
              u.profile_photo_url, u.created_at, u.updated_at,
              rl.availability, rl.timestamp as last_seen,
              rr.restaurant_id,
              r.name  as restaurant_name,
              ri.status as invitation_status,
              rinv.name as invited_by,
              (SELECT COUNT(*)            FROM orders WHERE rider_id = u.id AND status = 'delivered')                 as total_deliveries,
              (SELECT COUNT(*)            FROM orders WHERE rider_id = u.id AND status = 'delivered'
                AND created_at >= NOW() - INTERVAL '7 days')                                                          as this_week_deliveries,
              (SELECT COUNT(*)            FROM orders WHERE rider_id = u.id AND status = 'delivered'
                AND created_at >= NOW() - INTERVAL '30 days')                                                         as this_month_deliveries,
              (SELECT AVG(rating)::numeric(3,2) FROM ratings WHERE rider_id = u.id)                                   as average_rating
       FROM users u
       LEFT JOIN rider_locations    rl   ON rl.rider_id   = u.id
       LEFT JOIN restaurant_riders  rr   ON rr.rider_id   = u.id
       LEFT JOIN restaurants        r    ON r.id           = rr.restaurant_id
       LEFT JOIN rider_invitations  ri   ON ri.rider_email = u.email
       LEFT JOIN restaurants        rinv ON rinv.id        = ri.restaurant_id
       WHERE u.id = $1 AND u.role = 'rider'`,
      [id],
    );

    if (!riderResult.rows[0]) {
      res.status(404).json({ success: false, data: null, error: 'Rider not found' });
      return;
    }

    const deliveriesResult = await query(
      `SELECT o.id, o.status, o.total, o.created_at,
              r.name  as restaurant_name,
              u.display_name as customer_name
       FROM   orders o
       JOIN   restaurants r ON r.id = o.restaurant_id
       JOIN   users        u ON u.id = o.customer_id
       WHERE  o.rider_id = $1
       ORDER  BY o.created_at DESC
       LIMIT  10`,
      [id],
    );

    res.json(successResponse({
      ...riderResult.rows[0],
      // suspension_reason is not stored in a dedicated table — omit rather than crash
      suspension_reason: null,
      recent_deliveries: deliveriesResult.rows,
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
