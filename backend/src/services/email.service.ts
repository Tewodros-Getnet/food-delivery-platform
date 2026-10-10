import * as Brevo from '@getbrevo/brevo';
import { env } from '../config/env';
import { logger } from '../utils/logger';

// ── Brevo transactional email client ─────────────────────────────────────────
const apiInstance = new Brevo.TransactionalEmailsApi();
apiInstance.setApiKey(
  Brevo.TransactionalEmailsApiApiKeys.apiKey,
  env.BREVO_API_KEY,
);

const FROM_EMAIL = env.BREVO_FROM_EMAIL;
const FROM_NAME  = env.BREVO_FROM_NAME;

// ── OTP email ─────────────────────────────────────────────────────────────────
export async function sendOtpEmail(to: string, otp: string): Promise<void> {
  const mail = new Brevo.SendSmtpEmail();

  mail.sender      = { email: FROM_EMAIL, name: FROM_NAME };
  mail.to          = [{ email: to }];
  mail.subject     = 'Your verification code';
  mail.htmlContent = `
    <div style="font-family:Arial,sans-serif;max-width:480px;margin:0 auto;padding:24px;background:#fff;">
      <h2 style="color:#f97316;margin-bottom:4px;">${FROM_NAME}</h2>
      <p style="font-size:16px;color:#333;margin-top:0;">Your email verification code is:</p>
      <div style="background:#f3f4f6;border-radius:8px;padding:20px;text-align:center;margin:20px 0;">
        <span style="font-size:36px;font-weight:bold;letter-spacing:8px;color:#111;">${otp}</span>
      </div>
      <p style="font-size:14px;color:#666;">This code expires in <strong>10 minutes</strong>.</p>
      <p style="font-size:14px;color:#666;">If you did not request this, you can safely ignore this email.</p>
    </div>
  `;

  try {
    await apiInstance.sendTransacEmail(mail);
    logger.info('OTP email sent via Brevo', { to });
  } catch (err) {
    logger.error('Failed to send OTP email via Brevo', { to, error: String(err) });
    throw err;
  }
}

// ── Generic email (password reset links, etc.) ────────────────────────────────
export async function sendEmail(
  to: string,
  subject: string,
  html: string,
): Promise<void> {
  const mail = new Brevo.SendSmtpEmail();

  mail.sender      = { email: FROM_EMAIL, name: FROM_NAME };
  mail.to          = [{ email: to }];
  mail.subject     = subject;
  mail.htmlContent = html;

  try {
    await apiInstance.sendTransacEmail(mail);
    logger.info('Email sent via Brevo', { to, subject });
  } catch (err) {
    logger.error('Failed to send email via Brevo', { to, subject, error: String(err) });
    throw err;
  }
}