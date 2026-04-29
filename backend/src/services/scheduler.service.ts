import cron from 'node-cron';
import { query } from '../config/database';
import { logger } from '../utils/logger';
import { cleanupExpiredTokens } from './auth.service';

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
  // Use Intl API for correct timezone handling — no manual UTC offset
  const tz = 'Africa/Addis_Ababa';
  const now = new Date();

  const dayName = new Intl.DateTimeFormat('en-US', { weekday: 'long', timeZone: tz })
    .format(now)
    .toLowerCase();

  const hours = parseInt(
    new Intl.DateTimeFormat('en-US', { hour: 'numeric', hour12: false, timeZone: tz }).format(now),
    10
  );
  const minutes = parseInt(
    new Intl.DateTimeFormat('en-US', { minute: 'numeric', timeZone: tz }).format(now),
    10
  );
  const currentMinutes = hours * 60 + minutes;

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

// ── Expired refresh token cleanup job ────────────────────────────────────────
// Runs once per day at midnight — removes expired rows from refresh_tokens (Bug 13)
export function startTokenCleanupJob() {
  cron.schedule('0 0 * * *', async () => {
    try {
      await cleanupExpiredTokens();
    } catch (err) {
      logger.error('Token cleanup job failed', { error: String(err) });
    }
  });
}

// ── Stuck order alert job ─────────────────────────────────────────────────────
// Runs every 2 minutes — finds orders stuck at ready_for_pickup for 10+ minutes
// with no rider assigned, then emits admin:stuck_order to all admin sockets.
export function startStuckOrderAlertJob() {
  cron.schedule('*/2 * * * *', async () => {
    try {
      const stuck = await query<{
        id: string;
        restaurant_name: string;
        created_at: Date;
        minutes_waiting: number;
      }>(
        `SELECT o.id, r.name as restaurant_name, o.updated_at as created_at,
                EXTRACT(EPOCH FROM (NOW() - o.updated_at)) / 60 AS minutes_waiting
         FROM orders o
         JOIN restaurants r ON r.id = o.restaurant_id
         WHERE o.status = 'ready_for_pickup'
           AND o.rider_id IS NULL
           AND o.updated_at < NOW() - INTERVAL '10 minutes'`
      );

      if (!stuck.rowCount || stuck.rowCount === 0) return;

      const { emitAdminAlert } = await import('./socket.service');
      for (const order of stuck.rows) {
        emitAdminAlert({
          type: 'stuck_order',
          orderId: order.id,
          message: `Order from ${order.restaurant_name} has been waiting for a rider for ${Math.round(order.minutes_waiting)} minutes`,
        });
      }

      logger.info('Stuck order alerts emitted', { count: stuck.rowCount });
    } catch (err) {
      logger.error('Stuck order alert job failed', { error: String(err) });
    }
  });
}
