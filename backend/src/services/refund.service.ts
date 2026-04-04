import https from 'https';
import { env } from '../config/env';
import { query } from '../config/database';
import { logger } from '../utils/logger';

export async function initiateRefund(orderId: string, amount?: number): Promise<void> {
  const result = await query<{ payment_reference: string; total: number }>(
    'SELECT payment_reference, total FROM orders WHERE id = $1',
    [orderId]
  );
  const order = result.rows[0];
  if (!order?.payment_reference) {
    logger.warn('No payment reference found for refund', { orderId });
    return;
  }

  const refundAmount = amount ?? order.total;
  const body = JSON.stringify({
    tx_ref: order.payment_reference,
    amount: refundAmount,
  });

  return new Promise((resolve, reject) => {
    const req = https.request(
      {
        hostname: 'api.chapa.co',
        path: '/v1/transaction/refund',
        method: 'POST',
        headers: {
          Authorization: `Bearer ${env.CHAPA_SECRET_KEY}`,
          'Content-Type': 'application/json',
          'Content-Length': Buffer.byteLength(body),
        },
      },
      (res) => {
        let data = '';
        res.on('data', (chunk: Buffer) => { data += chunk.toString(); });
        res.on('end', () => {
          logger.info('Chapa refund response', { orderId, status: res.statusCode, data });
          resolve();
        });
      }
    );
    req.on('error', (err) => {
      logger.error('Chapa refund request failed', { orderId, error: String(err) });
      reject(err);
    });
    req.write(body);
    req.end();
  });
}
