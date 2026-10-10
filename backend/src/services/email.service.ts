import { env } from '../config/env';
import { logger } from '../utils/logger';

// ── SendLib Email Service (Gmail-based, Zero Domain Verification) ─────────────
// SendLib uses Gmail OAuth2 - no domain verification required!

interface SendLibEmailRequest {
  from: string;
  to: string;
  subject: string;
  html: string;
  text?: string;
}

interface SendLibResponse {
  success: boolean;
  message: string;
  id?: string;
  error?: string;
}

class SendLibService {
  private apiKey: string;
  private baseUrl: string = 'https://sendlib.samueltuoyo.com/api';

  constructor() {
    this.apiKey = env.SENDLIB_API_KEY || '';
    if (!this.apiKey) {
      throw new Error('SendLib API key not configured. Please set SENDLIB_API_KEY environment variable');
    }
  }

  async sendEmail(to: string, subject: string, html: string): Promise<void> {
    // Create text version from HTML (basic fallback)
    const textContent = html.replace(/<[^>]*>/g, '').replace(/\s+/g, ' ').trim();

    const emailData: SendLibEmailRequest = {
      from: env.SENDLIB_FROM_EMAIL || 'noreply@gmail.com', // Your connected Gmail
      to,
      subject,
      html,
      text: textContent
    };

    try {
      const response = await fetch(`${this.baseUrl}/send`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${this.apiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(emailData)
      });

      if (!response.ok) {
        const errorText = await response.text();
        throw new Error(`SendLib API error (${response.status}): ${errorText}`);
      }

      const result: SendLibResponse = await response.json();
      
      if (!result.success) {
        throw new Error(`SendLib delivery error: ${result.error || result.message}`);
      }

      logger.info('Email sent via SendLib', { 
        to, 
        subject, 
        messageId: result.id,
        from: emailData.from
      });
    } catch (err) {
      logger.error('Failed to send email via SendLib', { 
        to, 
        subject, 
        error: String(err) 
      });
      throw err;
    }
  }
}

// Create service instance
const sendLibService = new SendLibService();

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

  await sendLibService.sendEmail(to, 'Your verification code - Tana Delivery', html);
}

// ── Generic email (password reset links, etc.) ────────────────────────────────
export async function sendEmail(
  to: string,
  subject: string,
  html: string,
): Promise<void> {
  await sendLibService.sendEmail(to, subject, html);
}