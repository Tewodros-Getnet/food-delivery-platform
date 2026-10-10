import nodemailer from 'nodemailer';
import { env } from '../config/env';
import { logger } from '../utils/logger';

// ── Gmail SMTP Email Service (Temporary while Brevo account gets verified) ────

let transporter: any = null;

// Initialize transporter
function getTransporter() {
  if (!transporter) {
    transporter = nodemailer.createTransport({
      service: 'gmail',
      host: 'smtp.gmail.com', 
      port: 587,
      secure: false,
      auth: {
        user: 'tgetnet156@gmail.com', // Your Gmail
        pass: 'aoybtfqhjfvlkqsj', // Your app password
      },
    });
  }
  return transporter;
}

// ── OTP email ─────────────────────────────────────────────────────────────────
export async function sendOtpEmail(to: string, otp: string): Promise<void> {
  const html = `
    <div style="font-family:Arial,sans-serif;max-width:480px;margin:0 auto;padding:24px;background:#fff;">
      <h2 style="color:#f97316;margin-bottom:4px;">Tana Delivery</h2>
      <p style="font-size:16px;color:#333;margin-top:0;">Your email verification code is:</p>
      <div style="background:#f3f4f6;border-radius:8px;padding:20px;text-align:center;margin:20px 0;">
        <span style="font-size:36px;font-weight:bold;letter-spacing:8px;color:#111;">${otp}</span>
      </div>
      <p style="font-size:14px;color:#666;">This code expires in <strong>10 minutes</strong>.</p>
      <p style="font-size:14px;color:#666;">If you did not request this, you can safely ignore this email.</p>
    </div>
  `;

  try {
    const info = await getTransporter().sendMail({
      from: '"Tana Delivery" <tgetnet156@gmail.com>',
      to,
      subject: 'Your verification code',
      html,
    });
    
    logger.info('OTP email sent via Gmail SMTP', { to, messageId: info.messageId });
  } catch (err) {
    logger.error('Failed to send OTP email via Gmail SMTP', { to, error: String(err) });
    throw err;
  }
}

// ── Generic email (password reset links, etc.) ────────────────────────────────
export async function sendEmail(
  to: string,
  subject: string,
  html: string,
): Promise<void> {
  try {
    const info = await getTransporter().sendMail({
      from: '"Tana Delivery" <tgetnet156@gmail.com>',
      to,
      subject,
      html,
    });
    
    logger.info('Email sent via Gmail SMTP', { to, subject, messageId: info.messageId });
  } catch (err) {
    logger.error('Failed to send email via Gmail SMTP', { to, subject, error: String(err) });
    throw err;
  }
}
