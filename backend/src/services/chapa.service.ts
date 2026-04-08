import https from 'https';
import { env } from '../config/env';

export interface ChapaInitResponse {
  status: string;
  message: string;
  data: { checkout_url: string };
}

export async function initializePayment(params: {
  amount: number;
  currency: string;
  txRef: string;
  email: string;
  firstName: string;
  callbackUrl?: string;
  returnUrl?: string;
}): Promise<ChapaInitResponse> {
  const body = JSON.stringify({
    amount: params.amount,
    currency: params.currency || 'ETB',
    tx_ref: params.txRef,
    email: params.email,
    first_name: params.firstName,
    callback_url: params.callbackUrl,
    return_url: params.returnUrl,
  });

  return new Promise((resolve, reject) => {
    const req = https.request(
      {
        hostname: 'api.chapa.co',
        path: '/v1/transaction/initialize',
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
          try { resolve(JSON.parse(data) as ChapaInitResponse); }
          catch (e) { reject(e); }
        });
      }
    );
    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

export async function verifyPayment(txRef: string): Promise<{ status: string; amount: number }> {
  return new Promise((resolve, reject) => {
    const req = https.request(
      {
        hostname: 'api.chapa.co',
        path: `/v1/transaction/verify/${txRef}`,
        method: 'GET',
        headers: { Authorization: `Bearer ${env.CHAPA_SECRET_KEY}` },
      },
      (res) => {
        let data = '';
        res.on('data', (chunk: Buffer) => { data += chunk.toString(); });
        res.on('end', () => {
          try {
            const parsed = JSON.parse(data) as { status: string; data: { status: string; amount: number } };
            resolve({ status: parsed.data.status, amount: parsed.data.amount });
          } catch (e) { reject(e); }
        });
      }
    );
    req.on('error', reject);
    req.end();
  });
}

export function verifyWebhookSignature(payload: string, signature: string): boolean {
  const crypto = require('crypto') as typeof import('crypto');
  const expected = Buffer.from(env.CHAPA_WEBHOOK_SECRET);
  const received = Buffer.from(signature);
  if (expected.length !== received.length) return false;
  return crypto.timingSafeEqual(expected, received);
}
