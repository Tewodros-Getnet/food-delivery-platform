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

    // Anti-spam: Add sender reputation headers and improve content
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
          // Anti-spam: Add additional headers to improve reputation
          'User-Agent': 'Tana-Delivery-Platform/1.0',
        },
        body: JSON.stringify(emailData)
      });

      if (!response.ok) {
        const errorText = await response.text();
        throw new Error(`SendLib API error (${response.status}): ${errorText}`);
      }

      const result = await response.json() as SendLibResponse;
      
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
  // Anti-spam: Simple plain text with minimal styling
  const html = `
<div style="font-family: Arial, sans-serif; max-width: 500px; margin: 0 auto; padding: 20px; background: #ffffff;">
  <h2 style="color: #333333; font-size: 18px; margin: 0 0 15px 0;">Tana Delivery</h2>
  <p style="color: #333333; font-size: 14px; line-height: 1.4; margin: 0 0 15px 0;">
    Your verification code:
  </p>
  <p style="color: #333333; font-size: 24px; font-weight: bold; letter-spacing: 4px; margin: 15px 0; text-align: center;">
    ${otp}
  </p>
  <p style="color: #666666; font-size: 12px; line-height: 1.4; margin: 15px 0 0 0;">
    Code expires in 10 minutes. If you did not request this, ignore this email.
  </p>
</div>
  `;

  // Anti-spam: Plain, business-like subject
  await sendLibService.sendEmail(to, 'Verification code for Tana Delivery', html);
}

// ── Generic email (password reset links, etc.) ────────────────────────────────
export async function sendEmail(
  to: string,
  subject: string,
  html: string,
): Promise<void> {
  await sendLibService.sendEmail(to, subject, html);
}