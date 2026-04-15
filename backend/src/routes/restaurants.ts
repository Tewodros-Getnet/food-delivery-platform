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
