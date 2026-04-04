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
