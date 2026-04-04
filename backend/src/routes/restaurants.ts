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
