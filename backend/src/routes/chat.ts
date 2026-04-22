import { Router, Request, Response, NextFunction } from 'express';
import { body } from 'express-validator';
import { authenticate } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { query } from '../config/database';
import { successResponse, errorResponse } from '../utils/response';

const router = Router();

// GET /chat/:orderId — fetch message history for an order
// Accessible by the customer, rider, or restaurant owner of that order
router.get('/:orderId', authenticate, async (req: Request, res: Response, next: NextFunction) => {
  try {
    // Verify the caller is a participant of this order
    const orderResult = await query<{
      customer_id: string;
      rider_id: string | null;
      restaurant_id: string;
    }>(
      'SELECT customer_id, rider_id, restaurant_id FROM orders WHERE id = $1',
      [req.params.orderId]
    );
    const order = orderResult.rows[0];
    if (!order) { res.status(404).json(errorResponse('Order not found')); return; }

    // Check if caller is customer or rider
    const isCustomer = order.customer_id === req.userId;
    const isRider = order.rider_id === req.userId;

    // Check if caller is restaurant owner
    let isRestaurant = false;
    if (!isCustomer && !isRider) {
      const rResult = await query<{ owner_id: string }>(
        'SELECT owner_id FROM restaurants WHERE id = $1',
        [order.restaurant_id]
      );
      isRestaurant = rResult.rows[0]?.owner_id === req.userId;
    }

    if (!isCustomer && !isRider && !isRestaurant) {
      res.status(403).json(errorResponse('Forbidden'));
      return;
    }

    const messages = await query<{
      id: string;
      sender_id: string;
      sender_name: string | null;
      message: string;
      created_at: Date;
    }>(
      `SELECT cm.id, cm.sender_id, u.display_name as sender_name,
              cm.message, cm.created_at
       FROM chat_messages cm
       JOIN users u ON u.id = cm.sender_id
       WHERE cm.order_id = $1
       ORDER BY cm.created_at ASC`,
      [req.params.orderId]
    );

    res.json(successResponse(messages.rows));
  } catch (err) { next(err); }
});

// POST /chat/:orderId — send a message (REST fallback; primary path is socket)
router.post('/:orderId', authenticate, [
  body('message').trim().notEmpty(),
  validate,
], async (req: Request, res: Response, next: NextFunction) => {
  try {
    const orderResult = await query<{
      customer_id: string;
      rider_id: string | null;
      restaurant_id: string;
      status: string;
    }>(
      'SELECT customer_id, rider_id, restaurant_id, status FROM orders WHERE id = $1',
      [req.params.orderId]
    );
    const order = orderResult.rows[0];
    if (!order) { res.status(404).json(errorResponse('Order not found')); return; }

    const isCustomer = order.customer_id === req.userId;
    const isRider = order.rider_id === req.userId;
    if (!isCustomer && !isRider) {
      res.status(403).json(errorResponse('Forbidden'));
      return;
    }

    // Only allow chat while order is active
    const activeStatuses = ['rider_assigned', 'picked_up'];
    if (!activeStatuses.includes(order.status)) {
      res.status(409).json(errorResponse('Chat is only available during active delivery'));
      return;
    }

    const result = await query<{
      id: string; sender_id: string; message: string; created_at: Date;
    }>(
      `INSERT INTO chat_messages (order_id, sender_id, message)
       VALUES ($1, $2, $3) RETURNING *`,
      [req.params.orderId, req.userId, req.body.message as string]
    );

    const saved = result.rows[0];

    // Emit to the other participant via socket
    const { emitChatMessage } = await import('../services/socket.service');
    const recipientId = isCustomer ? order.rider_id : order.customer_id;
    if (recipientId) {
      emitChatMessage(recipientId, {
        orderId: req.params.orderId,
        messageId: saved.id,
        senderId: req.userId!,
        message: saved.message,
        createdAt: saved.created_at.toISOString(),
      });
    }

    res.status(201).json(successResponse(saved));
  } catch (err) { next(err); }
});

export default router;
