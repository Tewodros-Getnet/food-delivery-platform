import { Router, Request, Response, NextFunction } from 'express';
import { body } from 'express-validator';
import { authenticate } from '../middleware/auth';
import { authorize } from '../middleware/rbac';
import { validate } from '../middleware/validate';
import * as riderService from '../services/rider.service';
import { emitRiderLocationUpdate } from '../services/socket.service';
import { query } from '../config/database';
import { successResponse, errorResponse } from '../utils/response';

const router = Router();

// PUT /riders/location
router.put('/location', authenticate, authorize('rider'), [
  body('latitude').isFloat({ min: -90, max: 90 }),
  body('longitude').isFloat({ min: -180, max: 180 }),
  body('availability').isIn(['available', 'on_delivery', 'offline']),
  validate,
], async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { latitude, longitude, availability } = req.body as {
      latitude: number; longitude: number;
      availability: 'available' | 'on_delivery' | 'offline';
    };
    const location = await riderService.updateRiderLocation(req.userId!, latitude, longitude, availability);

    // If rider is on delivery, broadcast location to customer
    if (availability === 'on_delivery') {
      const activeOrder = await query<{ id: string; customer_id: string }>(
        `SELECT id, customer_id FROM orders WHERE rider_id = $1 AND status = 'picked_up' LIMIT 1`,
        [req.userId]
      );
      if (activeOrder.rows[0]) {
        emitRiderLocationUpdate({
          riderId: req.userId!,
          orderId: activeOrder.rows[0].id,
          customerId: activeOrder.rows[0].customer_id,
          latitude,
          longitude,
        });
      }
    }

    res.json(successResponse(location));
  } catch (err) { next(err); }
});

// PUT /riders/availability
router.put('/availability', authenticate, authorize('rider'), [
  body('availability').isIn(['available', 'on_delivery', 'offline']),
  validate,
], async (req: Request, res: Response, next: NextFunction) => {
  try {
    await riderService.setRiderAvailability(
      req.userId!,
      req.body.availability as 'available' | 'on_delivery' | 'offline'
    );
    res.json(successResponse({ message: 'Availability updated' }));
  } catch (err) { next(err); }
});

// GET /riders/available (internal use)
router.get('/available', authenticate, authorize('admin'), async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { lat, lon, radius } = req.query as Record<string, string>;
    const riders = await riderService.findNearbyRiders(
      parseFloat(lat), parseFloat(lon), parseFloat(radius ?? '5')
    );
    res.json(successResponse(riders));
  } catch (err) { next(err); }
});

export default router;
