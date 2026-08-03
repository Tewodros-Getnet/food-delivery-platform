import nodemailer from 'nodemailer';
import { env } from '../config/env';
import { logger } from '../utils/logger';

const transporter = nodemailer.createTransport({
  host: 'smtp.gmail.com',
  port: 587,
  secure: false,
  auth: {
    user: env.GMAIL_USER,
    pass: env.GMAIL_APP_PASSWORD,
  },
  tls: {
    rejectUnauthorized: true,
    minVersion: 'TLSv1.2',
  },
  connectionTimeout: 10000,
  greetingTimeout: 10000,
  socketTimeout: 15000,
  pool: true,        // keep connection alive — avoids reconnecting on every send
  maxConnections: 3,
  maxMessages: 100,
});

const FROM = `"Food Delivery" <${env.GMAIL_USER}>`;

export async function sendOtpEmail(to: string, otp: string): Promise<void> {
  try {
    await transporter.sendMail({
      from: FROM,
      to,
      subject: 'Your verification code',
      html: `
        <div style="font-family:Arial,sans-serif;max-width:480px;margin:0 auto;padding:24px;">
          <h2 style="color:#f97316;">Food Delivery</h2>
          <p style="font-size:16px;color:#333;">Your email verification code is:</p>
          <div style="background:#f3f4f6;border-radius:8px;padding:20px;text-align:center;margin:20px 0;">
            <span style="font-size:36px;font-weight:bold;letter-spacing:8px;color:#111;">${otp}</span>
          </div>
          <p style="font-size:14px;color:#666;">This code expires in <strong>10 minutes</strong>.</p>
          <p style="font-size:14px;color:#666;">If you did not request this, please ignore this email.</p>
        </div>
      `,
    });
    logger.info('OTP email sent', { to });
  } catch (err) {
    logger.error('Failed to send OTP email', { to, error: String(err) });
    throw err;
  }
}

export async function sendEmail(to: string, subject: string, html: string): Promise<void> {
  try {
    await transporter.sendMail({ from: FROM, to, subject, html });
    logger.info('Email sent', { to, subject });
  } catch (err) {
    logger.error('Failed to send email', { to, subject, error: String(err) });
    throw err;
  }
}
