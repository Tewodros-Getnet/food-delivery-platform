import { Router, Request, Response, NextFunction } from 'express';
import { authenticate } from '../middleware/auth';
import { authorize } from '../middleware/rbac';
import * as orderService from '../services/order.service';
import * as riderService from '../services/rider.service';
import { emitOrderStatusChanged, emitToRestaurant } from '../services/socket.service';
import { query } from '../config/database';
import { successResponse, errorResponse } from '../utils/response';

const router = Router();

// GET /deliveries/:id/details — fetch delivery request card data for a rider
router.get('/:id/details', authenticate, authorize('rider'), async (req: Request, res: Response, next: NextFunction) => {
  try {
    const order = await orderService.getOrderById(req.params.id);
    if (!order) { res.status(404).json(errorResponse('Order not found')); return; }
    if (order.status !== 'ready_for_pickup') {
      res.status(409).json(errorResponse('Order is no longer available'));
      return;
    }

    const [restaurantResult, addressResult] = await Promise.all([
      query<{ name: string; address: string; latitude: number; longitude: number }>(
        'SELECT name, address, latitude, longitude FROM restaurants WHERE id = $1',
        [order.restaurant_id]
      ),
      query<{ address_line: string; latitude: number; longitude: number }>(
        'SELECT address_line, latitude, longitude FROM addresses WHERE id = $1',
        [order.delivery_address_id]
      ),
    ]);

    const restaurant = restaurantResult.rows[0];
    const delivery = addressResult.rows[0];

    // Calculate distance for display
    const { haversineDistance } = await import('../utils/haversine');
    const distanceKm = restaurant && delivery
      ? haversineDistance(restaurant.latitude, restaurant.longitude, delivery.latitude, delivery.longitude)
      : 0;

    res.json(successResponse({
      orderId: order.id,
      restaurantName: restaurant?.name ?? 'Restaurant',
      restaurantAddress: restaurant?.address ?? '',
      customerAddress: delivery?.address_line ?? '',
      deliveryFee: order.delivery_fee,
      estimatedDistance: Math.round(distanceKm * 10) / 10,
    }));
  } catch (err) { next(err); }
});

// POST /deliveries/:id/accept
router.post('/:id/accept', authenticate, authorize('rider'), async (req: Request, res: Response, next: NextFunction) => {
  try {
    const order = await orderService.getOrderById(req.params.id);
    if (!order) { res.status(404).json(errorResponse('Order not found')); return; }
    if (order.status !== 'ready_for_pickup') {
      res.status(409).json(errorResponse('Order is no longer available for pickup'));
      return;
    }

    const updated = await orderService.updateOrderStatus(order.id, 'rider_assigned', {
      rider_id: req.userId,
    });

    // Mark rider as on_delivery using their last known location (avoids inserting bogus 0,0 coords)
    await riderService.setRiderAvailability(req.userId!, 'on_delivery');
    riderService.riderAccepted(order.id);

    // Fetch restaurant and delivery address coordinates for rider navigation
    const [restaurantResult, addressResult] = await Promise.all([
      query<{ latitude: number; longitude: number; name: string; address: string }>(
        'SELECT latitude, longitude, name, address FROM restaurants WHERE id = $1',
        [order.restaurant_id]
      ),
      query<{ latitude: number; longitude: number; address_line: string }>(
        'SELECT latitude, longitude, address_line FROM addresses WHERE id = $1',
        [order.delivery_address_id]
      ),
    ]);

    if (updated) {
      emitOrderStatusChanged(updated, order.customer_id);
      // Notify restaurant
      const rResult = await query<{ owner_id: string }>(
        'SELECT owner_id FROM restaurants WHERE id = $1', [order.restaurant_id]
      );
      if (rResult.rows[0]) emitToRestaurant(rResult.rows[0].owner_id, updated);
    }

    res.json(successResponse({
      order: updated,
      navigation: {
        restaurant: restaurantResult.rows[0] ?? null,
        delivery: addressResult.rows[0] ?? null,
      },
    }));
  } catch (err) { next(err); }
});

// POST /deliveries/:id/decline
router.post('/:id/decline', authenticate, authorize('rider'), async (req: Request, res: Response, next: NextFunction) => {
  try {
    const order = await orderService.getOrderById(req.params.id);
    if (!order) { res.status(404).json(errorResponse('Order not found')); return; }
    riderService.riderDeclined(order.id);
    res.json(successResponse({ message: 'Delivery request declined' }));
  } catch (err) { next(err); }
});

// PUT /deliveries/:id/pickup
router.put('/:id/pickup', authenticate, authorize('rider'), async (req: Request, res: Response, next: NextFunction) => {
  try {
    const order = await orderService.getOrderById(req.params.id);
    if (!order) { res.status(404).json(errorResponse('Order not found')); return; }
    if (order.rider_id !== req.userId) { res.status(403).json(errorResponse('Forbidden')); return; }
    if (order.status !== 'rider_assigned') {
      res.status(409).json(errorResponse('Order is not in rider_assigned status'));
      return;
    }

    const updated = await orderService.updateOrderStatus(order.id, 'picked_up');
    if (updated) emitOrderStatusChanged(updated, order.customer_id);
    res.json(successResponse(updated));
  } catch (err) { next(err); }
});

// PUT /deliveries/:id/deliver
router.put('/:id/deliver', authenticate, authorize('rider'), async (req: Request, res: Response, next: NextFunction) => {
  try {
    const order = await orderService.getOrderById(req.params.id);
    if (!order) { res.status(404).json(errorResponse('Order not found')); return; }
    if (order.rider_id !== req.userId) { res.status(403).json(errorResponse('Forbidden')); return; }
    if (order.status !== 'picked_up') {
      res.status(409).json(errorResponse('Order is not in picked_up status'));
      return;
    }

    const updated = await orderService.updateOrderStatus(order.id, 'delivered');
    await riderService.setRiderAvailability(req.userId!, 'available');
    if (updated) emitOrderStatusChanged(updated, order.customer_id);
    res.json(successResponse(updated));
  } catch (err) { next(err); }
});

export default router;
