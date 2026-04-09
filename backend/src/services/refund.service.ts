import axios, { AxiosError } from 'axios';
import { env } from '../config/env';
import { query } from '../config/database';
import { logger } from '../utils/logger';

const MAX_RETRIES = 3;
const BASE_DELAY_MS = 100;

async function sleep(ms: number) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

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
  const body = {
    tx_ref: order.payment_reference,
    amount: refundAmount,
  };

  let lastError: unknown;
  for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {
    try {
      const response = await axios.post(
        `${env.CHAPA_BASE_URL}/transaction/refund`,
        body,
        {
          headers: {
            Authorization: `Bearer ${env.CHAPA_SECRET_KEY}`,
            'Content-Type': 'application/json',
          },
        }
      );
      logger.info('Chapa refund response', { orderId, status: response.status, data: response.data });
      return;
    } catch (err) {
      const axiosErr = err as AxiosError;
      // Don't retry on 4xx client errors
      if (axiosErr.response && axiosErr.response.status >= 400 && axiosErr.response.status < 500) {
        logger.error('Chapa refund client error (no retry)', { orderId, status: axiosErr.response.status });
        throw err;
      }
      lastError = err;
      logger.warn(`Chapa refund attempt ${attempt} failed, retrying...`, { orderId, error: String(err) });
      if (attempt < MAX_RETRIES) {
        await sleep(BASE_DELAY_MS * Math.pow(2, attempt - 1));
      }
    }
  }

  logger.error('Chapa refund failed after all retries', { orderId, error: String(lastError) });
  throw lastError;
}
