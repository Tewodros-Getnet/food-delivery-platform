import admin from 'firebase-admin';
import { env } from '../config/env';
import { query } from '../config/database';
import { logger } from '../utils/logger';

let initialized = false;

function getApp(): admin.app.App {
  if (!initialized && env.FIREBASE_PROJECT_ID && env.FIREBASE_PRIVATE_KEY && env.FIREBASE_CLIENT_EMAIL) {
    admin.initializeApp({
      credential: admin.credential.cert({
        projectId: env.FIREBASE_PROJECT_ID,
        privateKey: env.FIREBASE_PRIVATE_KEY.replace(/\\n/g, '\n'),
        clientEmail: env.FIREBASE_CLIENT_EMAIL,
      }),
    });
    initialized = true;
  }
  return admin.app();
}

export async function sendPushNotification(
  userId: string,
  title: string,
  body: string,
  data?: Record<string, string>
): Promise<void> {
  try {
    const tokenResult = await query<{ token: string }>(
      'SELECT token FROM fcm_tokens WHERE user_id = $1',
      [userId]
    );
    if (!tokenResult.rows.length) return;

    const app = getApp();
    const messaging = app.messaging();

    const tokens = tokenResult.rows.map((r) => r.token);
    const message: admin.messaging.MulticastMessage = {
      tokens,
      notification: { title, body },
      data: data ?? {},
    };

    const response = await messaging.sendEachForMulticast(message);
    logger.info('FCM notification sent', {
      userId,
      successCount: response.successCount,
      failureCount: response.failureCount,
    });

    // Clean up invalid tokens
    const invalidTokens: string[] = [];
    response.responses.forEach((r, i) => {
      if (!r.success && (
        r.error?.code === 'messaging/invalid-registration-token' ||
        r.error?.code === 'messaging/registration-token-not-registered'
      )) {
        invalidTokens.push(tokens[i]);
      }
    });
    if (invalidTokens.length > 0) {
      await query(
        'DELETE FROM fcm_tokens WHERE token = ANY($1::text[])',
        [invalidTokens]
      );
    }
  } catch (err) {
    logger.error('FCM notification failed', { userId, error: String(err) });
    // Don't throw — push notification failure should not block the main operation
  }
}

export async function registerFcmToken(
  userId: string,
  token: string,
  deviceType: 'ios' | 'android' | 'web'
): Promise<void> {
  await query(
    `INSERT INTO fcm_tokens (user_id, token, device_type)
     VALUES ($1, $2, $3)
     ON CONFLICT (user_id, token) DO NOTHING`,
    [userId, token, deviceType]
  );
}
