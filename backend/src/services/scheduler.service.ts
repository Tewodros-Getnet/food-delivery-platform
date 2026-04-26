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

// ── Operating hours auto open/close job ──────────────────────────────────────
// Runs every minute — updates is_open for restaurants that have operating_hours set.
// Uses Addis Ababa timezone (Africa/Addis_Ababa = UTC+3).

function getCurrentAddisAbabaTime(): { dayName: string; currentMinutes: number } {
  // UTC+3 offset
  const now = new Date();
  const utcMs = now.getTime() + now.getTimezoneOffset() * 60 * 1000;
  const addisMs = utcMs + 3 * 60 * 60 * 1000;
  const addisDate = new Date(addisMs);

  const days = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'];
  const dayName = days[addisDate.getDay()];
  const currentMinutes = addisDate.getHours() * 60 + addisDate.getMinutes();

  return { dayName, currentMinutes };
}

function parseTimeToMinutes(time: string): number {
  const [h, m] = time.split(':').map(Number);
  return h * 60 + m;
}

export function startOperatingHoursJob() {
  cron.schedule('* * * * *', async () => {
    try {
      const { getRestaurantsWithOperatingHours } = await import('./restaurant.service');
      const restaurants = await getRestaurantsWithOperatingHours();
      if (restaurants.length === 0) return;

      const { dayName, currentMinutes } = getCurrentAddisAbabaTime();

      for (const restaurant of restaurants) {
        const hours = restaurant.operating_hours;
        const todaySchedule = hours[dayName as keyof typeof hours];

        let shouldBeOpen = false;

        if (todaySchedule && !('closed' in todaySchedule && todaySchedule.closed)) {
          const schedule = todaySchedule as { open: string; close: string };
          const openMinutes = parseTimeToMinutes(schedule.open);
          const closeMinutes = parseTimeToMinutes(schedule.close);
          shouldBeOpen = currentMinutes >= openMinutes && currentMinutes < closeMinutes;
        }

        // Only update if state needs to change (avoid unnecessary writes)
        if (shouldBeOpen !== restaurant.is_open) {
          await query(
            'UPDATE restaurants SET is_open = $1, updated_at = NOW() WHERE id = $2',
            [shouldBeOpen, restaurant.id]
          );
          logger.info('Auto-updated restaurant open status', {
            restaurantId: restaurant.id,
            is_open: shouldBeOpen,
            day: dayName,
            currentMinutes,
          });
        }
      }
    } catch (err) {
      logger.error('Operating hours job failed', { error: String(err) });
    }
  });
}
