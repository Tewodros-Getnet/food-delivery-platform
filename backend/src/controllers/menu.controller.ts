import { Request, Response, NextFunction } from 'express';
import { body } from 'express-validator';
import { validate } from '../middleware/validate';
import * as menuService from '../services/menu.service';
import * as restaurantService from '../services/restaurant.service';
import { successResponse, errorResponse } from '../utils/response';

export const createMenuItemValidation = [
  body('name').notEmpty().trim(),
  body('description').notEmpty().trim(),
  body('price').isFloat({ min: 0 }),
  body('category').notEmpty().trim(),
  body('imageBase64').notEmpty().withMessage('Image is required'),
  validate,
];

export const updateMenuItemValidation = [
  body('name').optional().trim(),
  body('price').optional().isFloat({ min: 0 }),
  body('category').optional().trim(),
  validate,
];

export async function createMenuItemHandler(req: Request, res: Response, next: NextFunction) {
  try {
    const restaurant = await restaurantService.getRestaurantById(req.params.restaurantId);
    if (!restaurant) { res.status(404).json(errorResponse('Restaurant not found')); return; }
    if (restaurant.owner_id !== req.userId) { res.status(403).json(errorResponse('Forbidden')); return; }
    if (restaurant.status !== 'approved') {
      res.status(403).json(errorResponse('Restaurant must be approved to add menu items'));
      return;
    }

    const item = await menuService.createMenuItem({
      restaurantId: req.params.restaurantId,
      name: req.body.name as string,
      description: req.body.description as string,
      price: parseFloat(req.body.price as string),
      category: req.body.category as string,
      imageBase64: req.body.imageBase64 as string,
    });
    res.status(201).json(successResponse(item));
  } catch (err) { next(err); }
}

export async function listMenuItemsHandler(req: Request, res: Response, next: NextFunction) {
  try {
    const { category } = req.query as Record<string, string>;
    const customerView = req.userRole === 'customer' || !req.userId;
    const items = await menuService.getMenuItems({
      restaurantId: req.params.restaurantId,
      category,
      customerView,
    });
    res.json(successResponse(items));
  } catch (err) { next(err); }
}

export async function updateMenuItemHandler(req: Request, res: Response, next: NextFunction) {
  try {
    const item = await menuService.getMenuItemById(req.params.id);
    if (!item) { res.status(404).json(errorResponse('Menu item not found')); return; }

    const restaurant = await restaurantService.getRestaurantById(item.restaurant_id);
    if (restaurant?.owner_id !== req.userId) { res.status(403).json(errorResponse('Forbidden')); return; }

    const updated = await menuService.updateMenuItem(req.params.id, req.body as Parameters<typeof menuService.updateMenuItem>[1]);
    res.json(successResponse(updated));
  } catch (err) { next(err); }
}

export async function deleteMenuItemHandler(req: Request, res: Response, next: NextFunction) {
  try {
    const item = await menuService.getMenuItemById(req.params.id);
    if (!item) { res.status(404).json(errorResponse('Menu item not found')); return; }

    const restaurant = await restaurantService.getRestaurantById(item.restaurant_id);
    if (restaurant?.owner_id !== req.userId) { res.status(403).json(errorResponse('Forbidden')); return; }

    const result = await menuService.deleteMenuItem(req.params.id);
    res.json(successResponse(result));
  } catch (err) { next(err); }
}

export async function toggleAvailabilityHandler(req: Request, res: Response, next: NextFunction) {
  try {
    const item = await menuService.getMenuItemById(req.params.id);
    if (!item) { res.status(404).json(errorResponse('Menu item not found')); return; }

    const restaurant = await restaurantService.getRestaurantById(item.restaurant_id);
    if (restaurant?.owner_id !== req.userId) { res.status(403).json(errorResponse('Forbidden')); return; }

    const updated = await menuService.toggleAvailability(req.params.id);
    res.json(successResponse(updated));
  } catch (err) { next(err); }
}
