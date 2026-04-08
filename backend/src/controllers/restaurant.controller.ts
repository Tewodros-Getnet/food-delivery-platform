import { Request, Response, NextFunction } from 'express';
import { body, query as qv } from 'express-validator';
import { validate } from '../middleware/validate';
import * as restaurantService from '../services/restaurant.service';
import { successResponse, errorResponse } from '../utils/response';

export const createValidation = [
  body('name').notEmpty().trim(),
  body('address').notEmpty().trim(),
  body('latitude').isFloat({ min: -90, max: 90 }),
  body('longitude').isFloat({ min: -180, max: 180 }),
  body('description').optional().trim(),
  body('category').optional().trim(),
  validate,
];

export async function createRestaurantHandler(req: Request, res: Response, next: NextFunction) {
  try {
    const restaurant = await restaurantService.createRestaurant({
      ownerId: req.userId!,
      name: req.body.name as string,
      description: req.body.description as string | undefined,
      address: req.body.address as string,
      latitude: parseFloat(req.body.latitude as string),
      longitude: parseFloat(req.body.longitude as string),
      category: req.body.category as string | undefined,
      logoBase64: req.body.logoBase64 as string | undefined,
      coverBase64: req.body.coverBase64 as string | undefined,
    });
    res.status(201).json(successResponse(restaurant));
  } catch (err) {
    next(err);
  }
}

export async function listRestaurantsHandler(req: Request, res: Response, next: NextFunction) {
  try {
    const { category, page, limit } = req.query as Record<string, string>;
    const result = await restaurantService.getRestaurants({
      category,
      page: page ? parseInt(page, 10) : 1,
      limit: limit ? parseInt(limit, 10) : 20,
    });
    res.json(successResponse(result));
  } catch (err) {
    next(err);
  }
}

const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

export async function getRestaurantHandler(req: Request, res: Response, next: NextFunction) {
  try {
    if (!UUID_REGEX.test(req.params.id)) {
      res.status(404).json(errorResponse('Restaurant not found'));
      return;
    }
    const restaurant = await restaurantService.getRestaurantById(req.params.id);
    if (!restaurant) {
      res.status(404).json(errorResponse('Restaurant not found'));
      return;
    }
    res.json(successResponse(restaurant));
  } catch (err) {
    next(err);
  }
}

export async function approveRestaurantHandler(req: Request, res: Response, next: NextFunction) {
  try {
    const restaurant = await restaurantService.updateRestaurantStatus(req.params.id, 'approved');
    if (!restaurant) { res.status(404).json(errorResponse('Restaurant not found')); return; }
    res.json(successResponse(restaurant));
  } catch (err) {
    next(err);
  }
}

export async function rejectRestaurantHandler(req: Request, res: Response, next: NextFunction) {
  try {
    const restaurant = await restaurantService.updateRestaurantStatus(req.params.id, 'rejected');
    if (!restaurant) { res.status(404).json(errorResponse('Restaurant not found')); return; }
    res.json(successResponse(restaurant));
  } catch (err) {
    next(err);
  }
}

export async function suspendRestaurantHandler(req: Request, res: Response, next: NextFunction) {
  try {
    await restaurantService.suspendRestaurant(req.params.id);
    res.json(successResponse({ message: 'Restaurant suspended' }));
  } catch (err) {
    next(err);
  }
}
