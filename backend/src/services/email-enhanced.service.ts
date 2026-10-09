import * as Brevo from '@getbrevo/brevo';
import nodemailer from 'nodemailer';
import { env } from '../config/env';
import { logger } from '../utils/logger';

// ── Enhanced email service with better error handling and fallbacks ──────────

interface EmailProvider {
  name: string;
  send: (to: string, subject: string, html: string) => Promise<void>;
}

// Brevo provider
class BrevoProvider implements EmailProvider {
  name = 'Brevo';
  private apiInstance: Brevo.TransactionalEmailsApi;

  constructor() {
    this.apiInstance = new Brevo.TransactionalEmailsApi();
    if (env.BREVO_API_KEY) {
      this.apiInstance.setApiKey(
        Brevo.TransactionalEmailsApiApiKeys.apiKey,
        env.BREVO_API_KEY
      );
    }
  }

  async send(to: string, subject: string, html: string): Promise<void> {
    if (!env.BREVO_API_KEY) {
      throw new Error('Brevo API key not configured');
    }

    const mail = new Brevo.SendSmtpEmail();
    mail.sender = { email: env.BREVO_FROM_EMAIL, name: env.BREVO_FROM_NAME };
    mail.to = [{ email: to }];
    mail.subject = subject;
    mail.htmlContent = html;

    try {
      const result = await this.apiInstance.sendTransacEmail(mail);
      logger.info('Email sent via Brevo', { to, subject, messageId: result.body?.messageId || 'success' });
    } catch (err: any) {
      // Enhanced error logging for Brevo
      const errorDetails = {
        to,
        subject,
        status: err.status,
        statusText: err.statusText,
        message: err.message,
        body: err.body,
      };
      logger.error('Brevo email failed', errorDetails);
      
      // Provide specific error messages
      if (err.status === 401) {
        throw new Error('Brevo API key is invalid or expired. Please check your API key at https://app.brevo.com/settings/keys/api');
      } else if (err.status === 400) {
        throw new Error(`Brevo request error: ${err.message}`);
      } else if (err.status === 403) {
        throw new Error('Brevo account suspended or insufficient permissions');
      } else {
        throw new Error(`Brevo API error (${err.status}): ${err.message}`);
      }
    }
  }
}

// Gmail SMTP provider (fallback)
class GmailProvider implements EmailProvider {
  name = 'Gmail SMTP';
  private transporter: any;

  constructor() {
    if (env.GMAIL_USER && env.GMAIL_APP_PASSWORD) {
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
    }
  }

  async send(to: string, subject: string, html: string): Promise<void> {
    if (!this.transporter) {
      throw new Error('Gmail SMTP not configured (missing GMAIL_USER or GMAIL_APP_PASSWORD)');
    }

    await this.transporter.sendMail({
      from: `"${env.BREVO_FROM_NAME || 'Tana Delivery'}" <${env.GMAIL_USER}>`,
      to,
      subject,
      html,
    });
    
    logger.info('Email sent via Gmail SMTP', { to, subject });
  }
}

// Email service with automatic fallback
class EmailService {
  private providers: EmailProvider[] = [];

  constructor() {
    // Add providers in order of preference
    this.providers.push(new BrevoProvider());
    this.providers.push(new GmailProvider());
  }

  async sendEmail(to: string, subject: string, html: string): Promise<void> {
    let lastError: Error | null = null;

    for (const provider of this.providers) {
      try {
        await provider.send(to, subject, html);
        logger.info(`Email sent successfully via ${provider.name}`, { to, subject });
        return; // Success - exit early
      } catch (err) {
        lastError = err as Error;
        logger.warn(`${provider.name} failed, trying next provider`, {
          to,
          subject,
          provider: provider.name,
          error: err instanceof Error ? err.message : String(err),
        });
      }
    }

    // All providers failed
    logger.error('All email providers failed', {
      to,
      subject,
      lastError: lastError?.message,
    });
    throw lastError || new Error('All email providers failed');
  }

  async sendOtpEmail(to: string, otp: string): Promise<void> {
    const html = `
      <div style="font-family:Arial,sans-serif;max-width:480px;margin:0 auto;padding:24px;background:#fff;">
        <h2 style="color:#f97316;margin-bottom:4px;">${env.BREVO_FROM_NAME || 'Tana Delivery'}</h2>
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

// Export the enhanced service
const emailService = new EmailService();

export const sendOtpEmail = (to: string, otp: string) => emailService.sendOtpEmail(to, otp);
export const sendEmail = (to: string, subject: string, html: string) => emailService.sendEmail(to, subject, html);