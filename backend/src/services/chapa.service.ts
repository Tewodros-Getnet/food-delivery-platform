import axios from 'axios';
import crypto from 'crypto';
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
  const response = await axios.post<ChapaInitResponse>(
    `${env.CHAPA_BASE_URL}/transaction/initialize`,
    {
      amount: params.amount,
      currency: params.currency || 'ETB',
      tx_ref: params.txRef,
      email: params.email,
      first_name: params.firstName,
      callback_url: params.callbackUrl,
      return_url: params.returnUrl,
    },
    {
      headers: {
        Authorization: `Bearer ${env.CHAPA_SECRET_KEY}`,
        'Content-Type': 'application/json',
      },
    }
  );
  return response.data;
}

export async function verifyPayment(txRef: string): Promise<{ status: string; amount: number }> {
  const response = await axios.get<{ status: string; data: { status: string; amount: number } }>(
    `${env.CHAPA_BASE_URL}/transaction/verify/${txRef}`,
    {
      headers: { Authorization: `Bearer ${env.CHAPA_SECRET_KEY}` },
    }
  );
  return { status: response.data.data.status, amount: response.data.data.amount };
}

export function verifyWebhookSignature(payload: string, signature: string): boolean {
  if (!signature) return false;
  const expected = crypto
    .createHmac('sha256', env.CHAPA_WEBHOOK_SECRET)
    .update(payload)
    .digest('hex');
  const expectedBuf = Buffer.from(expected);
  const signatureBuf = Buffer.from(signature);
  // timingSafeEqual requires same length — if lengths differ, signature is invalid
  if (expectedBuf.length !== signatureBuf.length) return false;
  return crypto.timingSafeEqual(expectedBuf, signatureBuf);
}
