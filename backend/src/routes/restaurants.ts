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
router.get('/', listRestaurantsHandler);
router.get('/:id', getRestaurantHandler);
router.get('/:id/ratings', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const ratings = await getRestaurantRatings(req.params.id);
    res.json(successResponse(ratings));
  } catch (err) { next(err); }
});
router.post('/', authenticate, authorize('restaurant'), createValidation, createRestaurantHandler);
router.post('/:id/approve', authenticate, authorize('admin'), approveRestaurantHandler);
router.post('/:id/reject', authenticate, authorize('admin'), rejectRestaurantHandler);
router.put('/:id/suspend', authenticate, authorize('admin'), suspendRestaurantHandler);

export default router;
