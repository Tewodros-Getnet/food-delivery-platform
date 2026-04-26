import { Request, Response, NextFunction } from 'express';
import { body } from 'express-validator';
import { validate } from '../middleware/validate';
import { acceptOrder, rejectOrder } from '../services/order.service';
import { successResponse } from '../utils/response';

export const rejectValidation = [
  body('reason').trim().notEmpty().withMessage('Rejection reason is required'),
  validate,
];

export const acceptValidation = [
  body('estimatedPrepTimeMinutes').optional().isInt({ min: 1 }).withMessage('Prep time must be a positive integer'),
  validate,
];

export async function acceptOrderHandler(req: Request, res: Response, next: NextFunction) {
  try {
    const order = await acceptOrder(
      req.params.id,
      req.userId!,
      req.body.estimatedPrepTimeMinutes as number | undefined
    );
    res.json(successResponse(order));
  } catch (err) {
    next(err);
  }
}

export async function rejectOrderHandler(req: Request, res: Response, next: NextFunction) {
  try {
    const order = await rejectOrder(
      req.params.id,
      req.userId!,
      req.body.reason as string
    );
    res.json(successResponse(order));
  } catch (err) {
    next(err);
  }
}
