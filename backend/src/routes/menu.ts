import { Router } from 'express';
import { authenticate } from '../middleware/auth';
import { authorize } from '../middleware/rbac';
import {
  createMenuItemHandler, createMenuItemValidation,
  listMenuItemsHandler,
  updateMenuItemHandler, updateMenuItemValidation,
  deleteMenuItemHandler,
  toggleAvailabilityHandler,
} from '../controllers/menu.controller';

const router = Router({ mergeParams: true });

// Mounted at /restaurants/:restaurantId/menu
router.get('/', listMenuItemsHandler);
router.post('/', authenticate, authorize('restaurant'), createMenuItemValidation, createMenuItemHandler);

// Mounted at /menu
const menuRouter = Router();
menuRouter.put('/:id', authenticate, authorize('restaurant'), updateMenuItemValidation, updateMenuItemHandler);
menuRouter.delete('/:id', authenticate, authorize('restaurant'), deleteMenuItemHandler);
menuRouter.put('/:id/availability', authenticate, authorize('restaurant'), toggleAvailabilityHandler);
// PATCH is the semantically correct verb for a partial update — kept alongside PUT for backward compatibility
menuRouter.patch('/:id/availability', authenticate, authorize('restaurant'), toggleAvailabilityHandler);

export { menuRouter };
export default router;
