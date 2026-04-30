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
      const activeOrder = await query<{
        id: string;
        customer_id: string;
        delivery_address_id: string;
      }>(
        `SELECT id, customer_id, delivery_address_id
         FROM orders WHERE rider_id = $1 AND status IN ('rider_assigned', 'picked_up') LIMIT 1`,
        [req.userId]
      );
      if (activeOrder.rows[0]) {
        const { id: orderId, customer_id, delivery_address_id } = activeOrder.rows[0];

        // Fetch customer delivery coordinates so client can compute remaining distance
        const addrResult = await query<{ latitude: number; longitude: number }>(
          'SELECT latitude, longitude FROM addresses WHERE id = $1',
          [delivery_address_id]
        );
        const addr = addrResult.rows[0];

        emitRiderLocationUpdate({
          riderId: req.userId!,
          orderId,
          customerId: customer_id,
          latitude,
          longitude,
          destinationLat: addr?.latitude ?? null,
          destinationLon: addr?.longitude ?? null,
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

// GET /riders/invitation — get pending invitation for this rider
router.get('/invitation', authenticate, authorize('rider'), async (req: Request, res: Response, next: NextFunction) => {
  try {
    const emailResult = await query<{ email: string }>(
      'SELECT email FROM users WHERE id = $1', [req.userId]
    );
    if (!emailResult.rows[0]) { res.status(404).json(errorResponse('User not found')); return; }
    const email = emailResult.rows[0].email;

    const result = await query(
      `SELECT ri.id, ri.restaurant_id, ri.status, ri.created_at,
              r.name as restaurant_name, r.address as restaurant_address
       FROM rider_invitations ri
       JOIN restaurants r ON r.id = ri.restaurant_id
       WHERE ri.rider_email = $1 AND ri.status = 'pending'
       ORDER BY ri.created_at DESC LIMIT 1`,
      [email]
    );
    res.json(successResponse(result.rows[0] ?? null));
  } catch (err) { next(err); }
});

// POST /riders/invitation/:id/accept
router.post('/invitation/:id/accept', authenticate, authorize('rider'), async (req: Request, res: Response, next: NextFunction) => {
  try {
    // Check rider is not already assigned
    const existing = await query(
      'SELECT restaurant_id FROM restaurant_riders WHERE rider_id = $1', [req.userId]
    );
    if (existing.rows[0]) {
      res.status(409).json(errorResponse('You are already assigned to a restaurant'));
      return;
    }

    const inv = await query<{ restaurant_id: string; rider_email: string; status: string }>(
      'SELECT * FROM rider_invitations WHERE id = $1', [req.params.id]
    );
    if (!inv.rows[0] || inv.rows[0].status !== 'pending') {
      res.status(404).json(errorResponse('Invitation not found or already handled'));
      return;
    }

    // Link rider to restaurant
    await query(
      'INSERT INTO restaurant_riders (rider_id, restaurant_id) VALUES ($1, $2)',
      [req.userId, inv.rows[0].restaurant_id]
    );
    // Mark invitation accepted
    await query(
      "UPDATE rider_invitations SET status = 'accepted' WHERE id = $1",
      [req.params.id]
    );
    res.json(successResponse({ message: 'Invitation accepted' }));
  } catch (err) { next(err); }
});

// POST /riders/invitation/:id/decline
router.post('/invitation/:id/decline', authenticate, authorize('rider'), async (req: Request, res: Response, next: NextFunction) => {
  try {
    await query(
      "UPDATE rider_invitations SET status = 'declined' WHERE id = $1",
      [req.params.id]
    );
    res.json(successResponse({ message: 'Invitation declined' }));
  } catch (err) { next(err); }
});

// GET /riders/earnings
router.get('/earnings', authenticate, authorize('rider'), async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { startDate, endDate } = req.query as { startDate?: string; endDate?: string };

    const conditions: string[] = ["o.rider_id = $1", "o.status = 'delivered'"];
    const values: unknown[] = [req.userId];
    let idx = 2;

    if (startDate) {
      conditions.push(`o.updated_at >= $${idx++}`);
      values.push(new Date(startDate));
    }
    if (endDate) {
      conditions.push(`o.updated_at <= $${idx++}`);
      values.push(new Date(endDate));
    }

    const where = conditions.join(' AND ');

    const result = await query<{
      id: string;
      delivery_fee: number;
      restaurant_name: string;
      address_line: string;
      updated_at: Date;
    }>(
      `SELECT o.id, o.delivery_fee, r.name as restaurant_name,
              a.address_line, o.updated_at
       FROM orders o
       JOIN restaurants r ON r.id = o.restaurant_id
       JOIN addresses a ON a.id = o.delivery_address_id
       WHERE ${where}
       ORDER BY o.updated_at DESC`,
      values
    );

    const deliveries = result.rows;
    const totalEarnings = deliveries.reduce((sum, d) => sum + Number(d.delivery_fee), 0);

    res.json(successResponse({
      totalDeliveries: deliveries.length,
      totalEarnings: Math.round(totalEarnings * 100) / 100,
      deliveries,
    }));
  } catch (err) { next(err); }
});

// GET /riders/profile
router.get('/profile', authenticate, authorize('rider'), async (req: Request, res: Response, next: NextFunction) => {
  try {
    const result = await query<{
      id: string; rider_id: string; license_number: string | null;
      vehicle_type: string | null; vehicle_plate: string | null;
      document_url: string | null; verified: boolean;
      created_at: Date; updated_at: Date;
    }>('SELECT * FROM rider_profiles WHERE rider_id = $1', [req.userId]);
    res.json(successResponse(result.rows[0] ?? {}));
  } catch (err) { next(err); }
});

// PUT /riders/profile
router.put('/profile', authenticate, authorize('rider'), [
  body('license_number').optional().trim(),
  body('vehicle_type').optional().trim(),
  body('vehicle_plate').optional().trim(),
  body('document_url').optional().trim().isURL(),
  validate,
], async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { license_number, vehicle_type, vehicle_plate, document_url } = req.body as {
      license_number?: string; vehicle_type?: string;
      vehicle_plate?: string; document_url?: string;
    };
    const result = await query(
      `INSERT INTO rider_profiles (rider_id, license_number, vehicle_type, vehicle_plate, document_url)
       VALUES ($1, $2, $3, $4, $5)
       ON CONFLICT (rider_id) DO UPDATE SET
         license_number = COALESCE(EXCLUDED.license_number, rider_profiles.license_number),
         vehicle_type = COALESCE(EXCLUDED.vehicle_type, rider_profiles.vehicle_type),
         vehicle_plate = COALESCE(EXCLUDED.vehicle_plate, rider_profiles.vehicle_plate),
         document_url = COALESCE(EXCLUDED.document_url, rider_profiles.document_url),
         updated_at = NOW()
       RETURNING *`,
      [req.userId, license_number ?? null, vehicle_type ?? null, vehicle_plate ?? null, document_url ?? null]
    );
    res.json(successResponse(result.rows[0]));
  } catch (err) { next(err); }
});

export default router;
