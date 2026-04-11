import { Router, Request, Response, NextFunction } from 'express';
import { body } from 'express-validator';
import { authenticate } from '../middleware/auth';
import { authorize } from '../middleware/rbac';
import { validate } from '../middleware/validate';
import * as orderService from '../services/order.service';
import { emitOrderStatusChanged, emitToRestaurant } from '../services/socket.service';
import { startDispatch } from '../services/rider.service';
import { initiateRefund } from '../services/refund.service';
import * as ratingService from '../services/rating.service';
import { query } from '../config/database';
import { successResponse, errorResponse } from '../utils/response';

const router = Router();

const createOrderValidation = [
  body('restaurantId').isUUID(),
  body('deliveryAddressId').isUUID(),
  body('items').isArray({ min: 1 }),
  body('items.*.menuItemId').isUUID(),
  body('items.*.quantity').isInt({ min: 1 }),
  validate,
];

// POST /orders
router.post('/', authenticate, authorize('customer'), createOrderValidation, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const result = await orderService.createOrder({
      customerId: req.userId!,
      restaurantId: req.body.restaurantId as string,
      deliveryAddressId: req.body.deliveryAddressId as string,
      items: req.body.items as Array<{ menuItemId: string; quantity: number }>,
    });
    res.status(201).json(successResponse(result));
  } catch (err) { next(err); }
});

// GET /orders
router.get('/', authenticate, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const orders = await orderService.getOrdersByUser(req.userId!, req.userRole!);
    res.json(successResponse(orders));
  } catch (err) { next(err); }
});

// GET /orders/:id
router.get('/:id', authenticate, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const order = await orderService.getOrderById(req.params.id);
    if (!order) { res.status(404).json(errorResponse('Order not found')); return; }
    res.json(successResponse(order));
  } catch (err) { next(err); }
});

// PUT /orders/:id/status (restaurant marks ready_for_pickup)
router.put('/:id/status', authenticate, authorize('restaurant'), [
  body('status').isIn(['ready_for_pickup']),
  body('estimatedPrepTime').optional().isInt({ min: 1 }),
  validate,
], async (req: Request, res: Response, next: NextFunction) => {
  try {
    const order = await orderService.getOrderById(req.params.id);
    if (!order) { res.status(404).json(errorResponse('Order not found')); return; }
    if (order.status !== 'confirmed') {
      res.status(409).json(errorResponse('Order cannot be updated from current status'));
      return;
    }
    const updated = await orderService.updateOrderStatus(order.id, 'ready_for_pickup', {
      estimated_prep_time_minutes: req.body.estimatedPrepTime as number | undefined,
    });
    if (updated) {
      emitOrderStatusChanged(updated, order.customer_id);
      // Notify restaurant owner so their order list updates in real-time
      const rResult = await query<{ owner_id: string }>(
        'SELECT owner_id FROM restaurants WHERE id = $1', [order.restaurant_id]
      );
      if (rResult.rows[0]) emitToRestaurant(rResult.rows[0].owner_id, updated);
      void startDispatch(order.id, order.restaurant_id);
    }
    res.json(successResponse(updated));
  } catch (err) { next(err); }
});

// PUT /orders/:id/cancel
router.put('/:id/cancel', authenticate, authorize('customer'), [
  body('reason').optional().trim(),
  validate,
], async (req: Request, res: Response, next: NextFunction) => {
  try {
    const order = await orderService.getOrderById(req.params.id);
    if (!order) { res.status(404).json(errorResponse('Order not found')); return; }
    if (order.customer_id !== req.userId) { res.status(403).json(errorResponse('Forbidden')); return; }

    if (['rider_assigned', 'picked_up'].includes(order.status)) {
      res.status(409).json(errorResponse('Cannot cancel order after rider has been assigned'));
      return;
    }
    if (!['confirmed', 'ready_for_pickup'].includes(order.status)) {
      res.status(409).json(errorResponse('Order cannot be cancelled in current status'));
      return;
    }

    const updated = await orderService.updateOrderStatus(order.id, 'cancelled', {
      cancellation_reason: req.body.reason as string | undefined,
      cancelled_at: new Date(),
    });

    // Notify restaurant if order was ready_for_pickup
    if (order.status === 'ready_for_pickup') {
      const rResult = await query<{ owner_id: string }>(
        'SELECT owner_id FROM restaurants WHERE id = $1', [order.restaurant_id]
      );
      if (updated && rResult.rows[0]) emitToRestaurant(rResult.rows[0].owner_id, updated);
    }

    // Initiate refund
    void initiateRefund(order.id);

    if (updated) emitOrderStatusChanged(updated, order.customer_id);
    res.json(successResponse(updated));
  } catch (err) { next(err); }
});

// POST /orders/:id/rate
router.post('/:id/rate', authenticate, authorize('customer'), [
  body('restaurantRating').optional().isInt({ min: 1, max: 5 }),
  body('riderRating').optional().isInt({ min: 1, max: 5 }),
  body('review').optional().trim(),
  validate,
], async (req: Request, res: Response, next: NextFunction) => {
  try {
    await ratingService.submitRating({
      orderId: req.params.id,
      customerId: req.userId!,
      restaurantRating: req.body.restaurantRating as number | undefined,
      riderRating: req.body.riderRating as number | undefined,
      review: req.body.review as string | undefined,
    });
    res.json(successResponse({ message: 'Rating submitted' }));
  } catch (err) { next(err); }
});

export default router;
