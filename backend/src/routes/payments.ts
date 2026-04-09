import { Router, Request, Response, NextFunction } from 'express';
import express from 'express';
import { authenticate } from '../middleware/auth';
import { authorize } from '../middleware/rbac';
import { query } from '../config/database';
import { calculateDeliveryFee } from '../utils/haversine';
import { env } from '../config/env';
import { successResponse, errorResponse } from '../utils/response';
import * as orderService from '../services/order.service';
import { initiateRefund } from '../services/refund.service';

const router = Router();

// GET /payments/estimate-fee?restaurant_id=&delivery_address_id=
router.get('/estimate-fee', authenticate, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { restaurant_id, delivery_address_id } = req.query as Record<string, string>;
    if (!restaurant_id || !delivery_address_id) {
      res.status(422).json(errorResponse('restaurant_id and delivery_address_id are required'));
      return;
    }

    const [rResult, aResult] = await Promise.all([
      query('SELECT latitude, longitude FROM restaurants WHERE id = $1', [restaurant_id]),
      query('SELECT latitude, longitude FROM addresses WHERE id = $1', [delivery_address_id]),
    ]);

    if (!rResult.rows[0]) { res.status(404).json(errorResponse('Restaurant not found')); return; }
    if (!aResult.rows[0]) { res.status(404).json(errorResponse('Address not found')); return; }

    const r = rResult.rows[0] as { latitude: number; longitude: number };
    const a = aResult.rows[0] as { latitude: number; longitude: number };

    const fee = calculateDeliveryFee(
      r.latitude, r.longitude,
      a.latitude, a.longitude,
      env.DELIVERY_BASE_FEE, env.DELIVERY_RATE_PER_KM
    );

    res.json(successResponse({ fee, currency: 'ETB' }));
  } catch (err) { next(err); }
});

// POST /payments/webhook — implemented in Task 7
// POST /payments/refund  — implemented in Task 12

// POST /payments/webhook (raw body needed for HMAC signature verification)
// NOTE: express.raw() here only works if this route is registered BEFORE
// the global express.json() middleware processes it. We handle this by
// checking if body is already a Buffer or re-stringifying if it's an object.
router.post('/webhook', express.raw({ type: '*/*' }), async (req: Request, res: Response, next: NextFunction) => {
  try {
    const signature = req.headers['x-chapa-signature'] as string || '';
    // Body may be a Buffer (raw) or already-parsed object (if json middleware ran first)
    let payload: string;
    if (Buffer.isBuffer(req.body)) {
      payload = req.body.toString('utf8');
    } else if (typeof req.body === 'string') {
      payload = req.body;
    } else {
      // Fallback: re-serialize — signature will still fail if order changed, but at least we try
      payload = JSON.stringify(req.body);
    }
    await orderService.handleWebhook(payload, signature);
    res.json({ received: true });
  } catch (err) { next(err); }
});

// POST /payments/refund (admin only)
router.post('/refund', authenticate, authorize('admin'), async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { orderId, amount } = req.body as { orderId: string; amount?: number };
    await initiateRefund(orderId, amount);
    res.json(successResponse({ message: 'Refund initiated' }));
  } catch (err) { next(err); }
});

export default router;
