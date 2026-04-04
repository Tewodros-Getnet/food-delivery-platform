import { Router, Request, Response, NextFunction } from 'express';
import { body } from 'express-validator';
import { authenticate } from '../middleware/auth';
import { authorize } from '../middleware/rbac';
import { validate } from '../middleware/validate';
import { query, withTransaction } from '../config/database';
import { initiateRefund } from '../services/refund.service';
import { emitDisputeResolved } from '../services/socket.service';
import { successResponse, errorResponse } from '../utils/response';

const router = Router();

// POST /disputes
router.post('/', authenticate, authorize('customer'), [
  body('orderId').isUUID(),
  body('reason').notEmpty().trim(),
  body('evidenceUrl').optional().isURL(),
  validate,
], async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { orderId, reason, evidenceUrl } = req.body as { orderId: string; reason: string; evidenceUrl?: string };

    const orderCheck = await query(
      'SELECT id FROM orders WHERE id = $1 AND customer_id = $2',
      [orderId, req.userId]
    );
    if (!orderCheck.rows[0]) { res.status(404).json(errorResponse('Order not found')); return; }

    const result = await query(
      `INSERT INTO disputes (order_id, customer_id, reason, evidence_url)
       VALUES ($1, $2, $3, $4) RETURNING *`,
      [orderId, req.userId, reason, evidenceUrl ?? null]
    );
    res.status(201).json(successResponse(result.rows[0]));
  } catch (err) { next(err); }
});

// GET /disputes (admin only)
router.get('/', authenticate, authorize('admin'), async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { status } = req.query as { status?: string };
    const conditions = status ? `WHERE d.status = $1` : '';
    const values = status ? [status] : [];

    const result = await query(
      `SELECT d.*, o.total as order_total, u.email as customer_email
       FROM disputes d
       JOIN orders o ON o.id = d.order_id
       JOIN users u ON u.id = d.customer_id
       ${conditions}
       ORDER BY d.created_at DESC`,
      values
    );
    res.json(successResponse(result.rows));
  } catch (err) { next(err); }
});

// PUT /disputes/:id/resolve (admin only)
router.put('/:id/resolve', authenticate, authorize('admin'), [
  body('resolution').isIn(['refund', 'partial_refund', 'no_action']),
  body('refundAmount').optional().isFloat({ min: 0 }),
  body('adminNotes').optional().trim(),
  validate,
], async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { resolution, refundAmount, adminNotes } = req.body as {
      resolution: 'refund' | 'partial_refund' | 'no_action';
      refundAmount?: number;
      adminNotes?: string;
    };

    await withTransaction(async (client) => {
      const disputeResult = await client.query(
        'SELECT * FROM disputes WHERE id = $1 AND status = $2',
        [req.params.id, 'open']
      );
      const dispute = disputeResult.rows[0] as { id: string; order_id: string; customer_id: string } | undefined;
      if (!dispute) {
        const err = new Error('Dispute not found or already resolved') as Error & { statusCode: number };
        err.statusCode = 404;
        throw err;
      }

      await client.query(
        `UPDATE disputes SET status = 'resolved', resolution = $1, refund_amount = $2,
         admin_notes = $3, resolved_at = NOW() WHERE id = $4`,
        [resolution, refundAmount ?? null, adminNotes ?? null, dispute.id]
      );

      if (resolution === 'refund' || resolution === 'partial_refund') {
        await initiateRefund(dispute.order_id, refundAmount);
      }

      emitDisputeResolved(dispute.customer_id, {
        disputeId: dispute.id,
        orderId: dispute.order_id,
        resolution,
        refundAmount,
        adminNotes,
      });
    });

    res.json(successResponse({ message: 'Dispute resolved' }));
  } catch (err) { next(err); }
});

export default router;
