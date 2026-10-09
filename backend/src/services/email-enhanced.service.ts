import nodemailer from 'nodemailer';
import { env } from '../config/env';
import { logger } from '../utils/logger';

// ── Gmail SMTP Email Service ──────────────────────────────────────────────────

class GmailEmailService {
  private transporter: any;

  constructor() {
    if (!env.GMAIL_USER || !env.GMAIL_APP_PASSWORD) {
      throw new Error('Gmail SMTP not configured. Please set GMAIL_USER and GMAIL_APP_PASSWORD environment variables');
    }

    this.transporter = nodemailer.createTransport({
      service: 'gmail',
      host: 'smtp.gmail.com',
      port: 587,
      secure: false,
      auth: {
        user: env.GMAIL_USER,
        pass: env.GMAIL_APP_PASSWORD,
      },
    });

    // Verify connection on startup
    this.verifyConnection();
  }

  private async verifyConnection(): Promise<void> {
    try {
      await this.transporter.verify();
      logger.info('Gmail SMTP connection verified successfully');
    } catch (err) {
      logger.error('Gmail SMTP connection failed', { error: String(err) });
    }
  }

  async sendEmail(to: string, subject: string, html: string): Promise<void> {
    try {
      const info = await this.transporter.sendMail({
        from: `"${env.FROM_NAME || 'Tana Delivery'}" <${env.GMAIL_USER}>`,
        to,
        subject,
        html,
      });
      
      logger.info('Email sent successfully via Gmail SMTP', { 
        to, 
        subject, 
        messageId: info.messageId 
      });
    } catch (err) {
      logger.error('Failed to send email via Gmail SMTP', { 
        to, 
        subject, 
        error: String(err) 
      });
      throw err;
    }
  }

  async sendOtpEmail(to: string, otp: string): Promise<void> {
    const html = `
      <div style="font-family:Arial,sans-serif;max-width:480px;margin:0 auto;padding:24px;background:#fff;">
        <h2 style="color:#f97316;margin-bottom:4px;">${env.FROM_NAME || 'Tana Delivery'}</h2>
        <p style="font-size:16px;color:#333;margin-top:0;">Your email verification code is:</p>
        <div style="background:#f3f4f6;border-radius:8px;padding:20px;text-align:center;margin:20px 0;">
          <span style="font-size:36px;font-weight:bold;letter-spacing:8px;color:#111;">${otp}</span>
        </div>
        <p style="font-size:14px;color:#666;">This code expires in <strong>10 minutes</strong>.</p>
        <p style="font-size:14px;color:#666;">If you did not request this, you can safely ignore this email.</p>
      </div>
    `;
    
    await this.sendEmail(to, 'Your verification code', html);
  }
}

// Export the Gmail email service
const emailService = new GmailEmailService();

export const sendOtpEmail = (to: string, otp: string) => emailService.sendOtpEmail(to, otp);
export const sendEmail = (to: string, subject: string, html: string) => emailService.sendEmail(to, subject, html);