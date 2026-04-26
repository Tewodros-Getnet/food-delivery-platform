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
// GET /menu/:id — fetch a single menu item (used by restaurant app modifier screen)
menuRouter.get('/:id', async (req: import('express').Request, res: import('express').Response, next: import('express').NextFunction) => {
  try {
    const { getMenuItemById } = await import('../services/menu.service');
    const { successResponse, errorResponse } = await import('../utils/response');
    const item = await getMenuItemById(req.params.id);
    if (!item) { res.status(404).json(errorResponse('Menu item not found')); return; }
    res.json(successResponse(item));
  } catch (err) { next(err); }
});
menuRouter.put('/:id/availability', authenticate, authorize('restaurant'), toggleAvailabilityHandler);
// PATCH is the semantically correct verb for a partial update — kept alongside PUT for backward compatibility
menuRouter.patch('/:id/availability', authenticate, authorize('restaurant'), toggleAvailabilityHandler);

// PUT /menu/:id/modifiers — replace all modifier groups for a menu item
menuRouter.put('/:id/modifiers', authenticate, authorize('restaurant'), async (req: import('express').Request, res: import('express').Response, next: import('express').NextFunction) => {
  try {
    const { query: dbQuery } = await import('../config/database');
    const { getMenuItemById } = await import('../services/menu.service');
    const { getRestaurantById } = await import('../services/restaurant.service');

    const item = await getMenuItemById(req.params.id);
    if (!item) { res.status(404).json({ success: false, data: null, error: 'Menu item not found' }); return; }

    const restaurant = await getRestaurantById(item.restaurant_id);
    if (restaurant?.owner_id !== req.userId) { res.status(403).json({ success: false, data: null, error: 'Forbidden' }); return; }

    const modifiers = req.body as unknown[];
    if (!Array.isArray(modifiers)) {
      res.status(422).json({ success: false, data: null, error: 'modifiers must be an array' });
      return;
    }

    const result = await dbQuery(
      `UPDATE menu_items SET modifiers = $1, updated_at = NOW() WHERE id = $2 RETURNING *`,
      [JSON.stringify(modifiers), req.params.id]
    );
    const { successResponse } = await import('../utils/response');
    res.json(successResponse(result.rows[0]));
  } catch (err) { next(err); }
});

export { menuRouter };
export default router;
