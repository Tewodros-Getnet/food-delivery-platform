import cron from 'node-cron';
import { query } from '../config/database';
import { logger } from '../utils/logger';

// Runs every 5 minutes — marks expired pending_payment orders as payment_failed
export function startPaymentExpiryJob() {
  cron.schedule('*/5 * * * *', async () => {
    try {
      const result = await query(
        `UPDATE orders
         SET status = 'payment_failed', updated_at = NOW()
         WHERE status = 'pending_payment'
         AND created_at < NOW() - INTERVAL '30 minutes'
         RETURNING id`
      );
      if (result.rowCount && result.rowCount > 0) {
        logger.info('Expired payment sessions marked as failed', { count: result.rowCount });
      }
    } catch (err) {
      logger.error('Payment expiry job failed', { error: String(err) });
    }
  });
}

// ── Acceptance timeout job ────────────────────────────────────────────────────
// Runs every 60 seconds — auto-cancels orders where restaurant didn't respond
// in time (acceptance_deadline has passed while still in pending_acceptance)

async function cancelExpiredOrder(
  orderId: string,
  customerId: string,
  restaurantId: string
): Promise<void> {
  try {
    // Atomic update — only cancels if still in pending_acceptance
    const result = await query(
      `UPDATE orders
       SET status = 'cancelled',
           cancellation_reason = 'Restaurant did not respond in time',
           cancelled_by = 'restaurant',
           cancelled_at = NOW(),
           updated_at = NOW()
       WHERE id = $1 AND status = 'pending_acceptance'
       RETURNING *`,
      [orderId]
    );

    if (!result.rows[0]) return; // Already handled (accepted/rejected) — skip

    const cancelled = result.rows[0] as import('../models/order.model').Order;

    // Fire-and-forget refund
    const { initiateRefund } = await import('./refund.service');
    void initiateRefund(orderId);

    // Notify customer via socket + FCM
    const { emitOrderStatusChanged } = await import('./socket.service');
    const { sendPushNotification } = await import('./fcm.service');

    emitOrderStatusChanged(cancelled, customerId);
    void sendPushNotification(
      customerId,
      'Order Cancelled',
      'The restaurant did not respond in time. A refund has been initiated.',
      { type: 'order_cancelled', orderId }
    );

    // Notify restaurant owner via FCM
    const ownerResult = await query<{ owner_id: string }>(
      'SELECT owner_id FROM restaurants WHERE id = $1', [restaurantId]
    );
    if (ownerResult.rows[0]) {
      void sendPushNotification(
        ownerResult.rows[0].owner_id,
        'Order Expired',
        'An order expired before you could respond.',
        { type: 'order_expired', orderId }
      );
    }

    logger.info('Auto-cancelled expired pending_acceptance order', { orderId });
  } catch (err) {
    logger.error('Failed to cancel expired order', { orderId, error: String(err) });
  }
}

export function startAcceptanceTimeoutJob() {
  cron.schedule('* * * * *', async () => {
    try {
      const expired = await query<{ id: string; customer_id: string; restaurant_id: string }>(
        `SELECT id, customer_id, restaurant_id
         FROM orders
         WHERE status = 'pending_acceptance'
           AND acceptance_deadline < NOW()`
      );

      if (expired.rowCount && expired.rowCount > 0) {
        logger.info('Processing expired acceptance orders', { count: expired.rowCount });
        for (const order of expired.rows) {
          await cancelExpiredOrder(order.id, order.customer_id, order.restaurant_id);
        }
      }
    } catch (err) {
      logger.error('Acceptance timeout job failed', { error: String(err) });
    }
  });
}
