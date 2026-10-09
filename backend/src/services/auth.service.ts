import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import crypto from 'crypto';
import { v4 as uuidv4 } from 'uuid';
import { PoolClient } from 'pg';
import { query, withTransaction } from '../config/database';
import { env } from '../config/env';
import { User, PublicUser, UserRole } from '../models/user.model';
import { sendOtpEmail, sendEmail } from './email-enhanced.service';
import { verifyGoogleIdToken } from './google-auth.service';
import { logger } from '../utils/logger';

// ── Per-user resend-OTP rate limit ────────────────────────────────────────────
// Tracks the last time a resend was issued per userId (in-memory).
// Resets on server restart which is acceptable for this use case.
const RESEND_COOLDOWN_MS = 60 * 1000; // 60 seconds
const resendLastSent = new Map<string, number>();

export function checkResendCooldown(userId: string): void {
  const last = resendLastSent.get(userId);
  if (last !== undefined) {
    const elapsed = Date.now() - last;
    if (elapsed < RESEND_COOLDOWN_MS) {
      const remaining = Math.ceil((RESEND_COOLDOWN_MS - elapsed) / 1000);
      const err = new Error(`Please wait ${remaining}s before requesting another code`) as Error & { statusCode: number };
      err.statusCode = 429;
      throw err;
    }
  }
  resendLastSent.set(userId, Date.now());
}

// ── Password reset token expiry ───────────────────────────────────────────────
const RESET_TOKEN_EXPIRY_MINUTES = 30;

const BCRYPT_ROUNDS = 10;
const OTP_EXPIRY_MINUTES = 10;


export interface AuthTokens {
  jwt: string;
  refreshToken: string;
}

export interface AuthResult {
  user: PublicUser;
  tokens: AuthTokens;
}

function generateJwt(userId: string, role: string): string {
  return jwt.sign({ userId, role }, env.JWT_SECRET, {
    expiresIn: env.JWT_EXPIRY as jwt.SignOptions['expiresIn'],
  });
}

function generateRefreshToken(): { raw: string; hash: string } {
  const raw = uuidv4();
  const hash = crypto.createHash('sha256').update(raw).digest('hex');
  return { raw, hash };
}

function toPublicUser(user: User): PublicUser {
  return {
    id: user.id,
    email: user.email,
    role: user.role,
    display_name: user.display_name,
    phone: user.phone,
    profile_photo_url: user.profile_photo_url,
    status: user.status,
    provider: user.provider,
    created_at: user.created_at,
  };
}

function generateOtp(): string {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

async function storeOtp(userId: string, client?: PoolClient): Promise<string> {
  const otp = generateOtp();
  const expiresAt = new Date(Date.now() + OTP_EXPIRY_MINUTES * 60 * 1000);
  const run = client
    ? (text: string, params: unknown[]) => client.query(text, params)
    : (text: string, params: unknown[]) => query(text, params);
  await run('UPDATE verification_codes SET used = TRUE WHERE user_id = $1 AND used = FALSE', [userId]);
  await run(
    'INSERT INTO verification_codes (user_id, code, expires_at) VALUES ($1, $2, $3)',
    [userId, otp, expiresAt]
  );
  return otp;
}

export async function register(
  email: string,
  password: string,
  role: UserRole
): Promise<{ userId: string; email: string; pendingVerification: true }> {
  // Store OTP inside transaction, send email OUTSIDE to avoid holding DB connection
  // open while waiting for SMTP which can cause transaction timeout
  const { userId, otp } = await withTransaction(async (client) => {
    const existing = await client.query(
      'SELECT id, email_verified FROM users WHERE email = $1',
      [email]
    );
    if (existing.rowCount && existing.rowCount > 0) {
      const existingUser = existing.rows[0] as { id: string; email_verified: boolean };
      if (!existingUser.email_verified) {
        const otp = await storeOtp(existingUser.id, client);
        return { userId: existingUser.id, otp };
      }
      const err = new Error('Email already registered') as Error & { statusCode: number };
      err.statusCode = 409;
      throw err;
    }

    const password_hash = await bcrypt.hash(password, BCRYPT_ROUNDS);
    const result = await client.query<User>(
      `INSERT INTO users (email, password_hash, role, email_verified)
       VALUES ($1, $2, $3, FALSE) RETURNING *`,
      [email, password_hash, role]
    );
    const user = result.rows[0];
    const otp = await storeOtp(user.id, client);
    return { userId: user.id, otp };
  });

  // Send email after transaction is committed — fire-and-forget so a transient
  // SMTP failure never blocks registration. The user lands on the OTP screen
  // and can hit "Resend" if the email didn't arrive.
  sendOtpEmail(email, otp).catch((err) =>
    logger.error('OTP email delivery failed — user can resend', { userId, email, error: String(err) })
  );

  return { userId, email, pendingVerification: true };
}

const MAX_OTP_ATTEMPTS = 5;

export async function verifyOtp(userId: string, code: string): Promise<AuthResult> {
  const result = await query<{ id: string; code: string; expires_at: Date; used: boolean; attempts: number }>(
    `SELECT * FROM verification_codes
     WHERE user_id = $1 AND used = FALSE
     ORDER BY created_at DESC LIMIT 1`,
    [userId]
  );
  const record = result.rows[0];

  if (!record) {
    const err = new Error('No verification code found') as Error & { statusCode: number };
    err.statusCode = 400;
    throw err;
  }
  if (new Date() > record.expires_at) {
    const err = new Error('Verification code has expired. Please request a new one.') as Error & { statusCode: number };
    err.statusCode = 400;
    throw err;
  }

  // Increment attempt counter before checking — prevents timing oracle
  const attempts = (record.attempts ?? 0) + 1;
  await query('UPDATE verification_codes SET attempts = $1 WHERE id = $2', [attempts, record.id]);

  if (attempts > MAX_OTP_ATTEMPTS) {
    // Mark code as used so they can't keep trying
    await query('UPDATE verification_codes SET used = TRUE WHERE id = $1', [record.id]);
    const err = new Error('Too many incorrect attempts. Please request a new code.') as Error & { statusCode: number };
    err.statusCode = 429;
    throw err;
  }

  // Timing-safe comparison — prevents timing-based OTP enumeration attacks
  const recordBuf = Buffer.from(record.code, 'utf8');
  const inputBuf = Buffer.from(code.padEnd(record.code.length, '\0').slice(0, record.code.length), 'utf8');
  const codesMatch = recordBuf.length === inputBuf.length && crypto.timingSafeEqual(recordBuf, inputBuf);
  if (!codesMatch) {
    const remaining = MAX_OTP_ATTEMPTS - attempts;
    const err = new Error(
      remaining > 0
        ? `Invalid code. ${remaining} attempt${remaining === 1 ? '' : 's'} remaining.`
        : 'Too many incorrect attempts. Please request a new code.'
    ) as Error & { statusCode: number };
    err.statusCode = 400;
    throw err;
  }

  // Mark code as used and verify email
  await query('UPDATE verification_codes SET used = TRUE WHERE id = $1', [record.id]);
  await query('UPDATE users SET email_verified = TRUE, updated_at = NOW() WHERE id = $1', [userId]);

  // Now issue tokens
  const userResult = await query<User>('SELECT * FROM users WHERE id = $1', [userId]);
  const user = userResult.rows[0];

  const jwtToken = generateJwt(user.id, user.role);
  const { raw, hash } = generateRefreshToken();
  const expiresAt = new Date();
  expiresAt.setDate(expiresAt.getDate() + 7);
  // Delete all existing tokens for this user before inserting new one (Bug 13)
  await query('DELETE FROM refresh_tokens WHERE user_id = $1', [user.id]);
  await query(
    'INSERT INTO refresh_tokens (user_id, token_hash, expires_at) VALUES ($1, $2, $3)',
    [user.id, hash, expiresAt]
  );

  return { user: toPublicUser(user), tokens: { jwt: jwtToken, refreshToken: raw } };
}

export async function resendOtp(userId: string): Promise<void> {
  // Enforce server-side per-user cooldown (fix #4)
  checkResendCooldown(userId);
  await resendOtpInternal(userId);
}

// Used by admin routes — bypasses the cooldown
export async function resendOtpInternal(userId: string): Promise<void> {
  const userResult = await query<{ email: string; email_verified: boolean }>(
    'SELECT email, email_verified FROM users WHERE id = $1', [userId]
  );
  const user = userResult.rows[0];
  if (!user) {
    const err = new Error('User not found') as Error & { statusCode: number };
    err.statusCode = 404;
    throw err;
  }
  if (user.email_verified) {
    const err = new Error('Email already verified') as Error & { statusCode: number };
    err.statusCode = 400;
    throw err;
  }
  const otp = await storeOtp(userId);
  await sendOtpEmail(user.email, otp);
}

export async function login(email: string, password: string): Promise<AuthResult> {
  const result = await query<User>(
    'SELECT * FROM users WHERE email = $1',
    [email]
  );

  const user = result.rows[0];
  const unauthorized = new Error('Invalid credentials') as Error & { statusCode: number };
  unauthorized.statusCode = 401;

  if (!user) throw unauthorized;
  if (user.status === 'suspended') {
    const err = new Error('Account suspended') as Error & { statusCode: number };
    err.statusCode = 401;
    throw err;
  }

  // Check if this is a Google account trying to use password login
  if (user.provider === 'google') {
    const err = new Error('This account uses Google Sign-In. Please sign in with Google.') as Error & { statusCode: number };
    err.statusCode = 400;
    throw err;
  }

  const valid = await bcrypt.compare(password, user.password_hash!);
  if (!valid) throw unauthorized;

  // Email verification check AFTER password validation (to avoid leaking account existence)
  if (!user.email_verified) {
    const err = new Error('Please verify your email before logging in') as Error & { statusCode: number };
    err.statusCode = 403;
    throw err;
  }

  const jwtToken = generateJwt(user.id, user.role);
  const { raw, hash } = generateRefreshToken();

  const expiresAt = new Date();
  expiresAt.setDate(expiresAt.getDate() + 7);

  // Delete all existing tokens for this user before inserting new one (Bug 13)
  await query('DELETE FROM refresh_tokens WHERE user_id = $1', [user.id]);
  await query(
    `INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
     VALUES ($1, $2, $3)`,
    [user.id, hash, expiresAt]
  );

  return { user: toPublicUser(user), tokens: { jwt: jwtToken, refreshToken: raw } };
}

export async function refresh(rawToken: string): Promise<{ jwt: string; refreshToken: string }> {
  const hash = crypto.createHash('sha256').update(rawToken).digest('hex');

  const result = await query(
    `SELECT rt.*, u.role, u.status FROM refresh_tokens rt
     JOIN users u ON u.id = rt.user_id
     WHERE rt.token_hash = $1 AND rt.expires_at > NOW()`,
    [hash]
  );

  if (!result.rows[0]) {
    const err = new Error('Invalid or expired refresh token') as Error & { statusCode: number };
    err.statusCode = 401;
    throw err;
  }

  const { user_id, role, status, expires_at } = result.rows[0] as {
    user_id: string; role: string; status: string; expires_at: Date;
  };

  if (status === 'suspended') {
    const err = new Error('Account suspended') as Error & { statusCode: number };
    err.statusCode = 401;
    throw err;
  }

  // Rotate: delete the consumed token and issue a fresh one
  // This ensures a stolen refresh token becomes invalid after first use
  await query('DELETE FROM refresh_tokens WHERE token_hash = $1', [hash]);

  const { raw: newRaw, hash: newHash } = generateRefreshToken();
  // Preserve the original expiry so rotation doesn't extend the session
  await query(
    'INSERT INTO refresh_tokens (user_id, token_hash, expires_at) VALUES ($1, $2, $3)',
    [user_id, newHash, expires_at]
  );

  return { jwt: generateJwt(user_id, role), refreshToken: newRaw };
}

export async function logout(rawToken: string): Promise<void> {
  const hash = crypto.createHash('sha256').update(rawToken).digest('hex');
  await query('DELETE FROM refresh_tokens WHERE token_hash = $1', [hash]);
}

export async function cleanupExpiredTokens(): Promise<void> {
  const result = await query('DELETE FROM refresh_tokens WHERE expires_at < NOW()');
  logger.info('Cleaned up expired refresh tokens', { deleted: result.rowCount ?? 0 });
}

// ── Password reset ────────────────────────────────────────────────────────────

export async function requestPasswordReset(email: string): Promise<void> {
  // Always resolve successfully — never reveal whether an email exists
  const userResult = await query<{ id: string; email: string; role: string }>(
    'SELECT id, email, role FROM users WHERE email = $1', [email]
  );
  const user = userResult.rows[0];
  if (!user) return; // Silent — don't leak account existence

  // Invalidate any existing unexpired tokens for this user
  await query(
    'UPDATE password_reset_tokens SET used = TRUE WHERE user_id = $1 AND used = FALSE',
    [user.id]
  );

  // Generate a secure random token
  const rawToken = crypto.randomBytes(32).toString('hex');
  const tokenHash = crypto.createHash('sha256').update(rawToken).digest('hex');
  const expiresAt = new Date(Date.now() + RESET_TOKEN_EXPIRY_MINUTES * 60 * 1000);

  await query(
    `INSERT INTO password_reset_tokens (user_id, token_hash, expires_at)
     VALUES ($1, $2, $3)`,
    [user.id, tokenHash, expiresAt]
  );

  // Generate role-specific deep link
  const getRoleSpecificLink = (role: string, token: string) => {
    switch (role) {
      case 'customer':
        return `fooddelivery://customer/reset-password?token=${token}`;
      case 'restaurant':
        return `fooddelivery://restaurant/reset-password?token=${token}`;
      case 'rider':
        return `fooddelivery://rider/reset-password?token=${token}`;
      default:
        return `fooddelivery://app/reset-password?token=${token}`;
    }
  };

  const resetLink = getRoleSpecificLink(user.role, rawToken);
  
  // Also provide web fallback links
  const webFallbackLinks = {
    customer: `${env.APP_DEEP_LINK_BASE?.replace('fooddelivery://app', 'https://customer.tanadelivery.com')}/reset-password?token=${rawToken}`,
    restaurant: `${env.APP_DEEP_LINK_BASE?.replace('fooddelivery://app', 'https://restaurant.tanadelivery.com')}/reset-password?token=${rawToken}`,
    rider: `${env.APP_DEEP_LINK_BASE?.replace('fooddelivery://app', 'https://rider.tanadelivery.com')}/reset-password?token=${rawToken}`,
  };

  const roleTitle = user.role.charAt(0).toUpperCase() + user.role.slice(1);
  const webLink = webFallbackLinks[user.role as keyof typeof webFallbackLinks] || resetLink;

  await sendEmail(
    user.email,
    `Reset Your Password - Tana Delivery ${roleTitle} App`,
    `
    <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; max-width: 600px; margin: 0 auto; background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); border-radius: 20px; overflow: hidden;">
      <!-- Header -->
      <div style="background: rgba(255,255,255,0.1); backdrop-filter: blur(10px); padding: 32px 40px; text-align: center;">
        <div style="width: 80px; height: 80px; background: white; border-radius: 50%; margin: 0 auto 16px; display: flex; align-items: center; justify-content: center;">
          <svg width="40" height="40" viewBox="0 0 24 24" fill="none">
            <path d="M12 2L13.09 8.26L22 9L13.09 9.74L12 16L10.91 9.74L2 9L10.91 8.26L12 2Z" fill="#CC1A1A"/>
            <circle cx="12" cy="18" r="4" fill="#CC1A1A"/>
          </svg>
        </div>
        <h1 style="color: white; font-size: 28px; font-weight: 700; margin: 0; letter-spacing: -0.5px;">Tana Delivery</h1>
        <p style="color: rgba(255,255,255,0.8); font-size: 16px; margin: 8px 0 0;">${roleTitle} App - Reset Your Password</p>
      </div>

      <!-- Content -->
      <div style="background: white; padding: 40px;">
        <div style="text-align: center; margin-bottom: 32px;">
          <h2 style="color: #1f2937; font-size: 24px; font-weight: 600; margin: 0 0 8px;">Forgot your password?</h2>
          <p style="color: #6b7280; font-size: 16px; margin: 0; line-height: 1.5;">No worries! We'll help you reset it securely for your ${roleTitle} account.</p>
        </div>

        <div style="background: #f8fafc; border: 2px dashed #e2e8f0; border-radius: 12px; padding: 24px; margin: 24px 0; text-align: center;">
          <p style="color: #374151; font-size: 14px; margin: 0 0 20px; line-height: 1.5;">Click the button below to open the ${roleTitle} app and create a new password. This link is valid for <strong>${RESET_TOKEN_EXPIRY_MINUTES} minutes</strong> only.</p>
          
          <a href="${resetLink}" 
             style="display: inline-block; background: linear-gradient(135deg, #CC1A1A 0%, #e11d48 100%); color: white; padding: 16px 32px; border-radius: 12px; text-decoration: none; font-weight: 600; font-size: 16px; box-shadow: 0 4px 12px rgba(204, 26, 26, 0.3); transition: transform 0.2s; margin-bottom: 16px;">
            🔑 Open ${roleTitle} App & Reset Password
          </a>
          
          <div style="margin-top: 20px; padding-top: 16px; border-top: 1px solid #e5e7eb;">
            <p style="color: #6b7280; font-size: 12px; margin: 0 0 8px;">Having trouble with the app? Use this web link instead:</p>
            <a href="${webLink}" 
               style="color: #CC1A1A; font-size: 12px; text-decoration: underline;">
              ${webLink}
            </a>
          </div>
        </div>

        <!-- Security Info -->
        <div style="background: #fffbeb; border-left: 4px solid #f59e0b; padding: 16px; margin: 24px 0; border-radius: 0 8px 8px 0;">
          <h4 style="color: #92400e; font-size: 14px; font-weight: 600; margin: 0 0 8px;">🛡️ Security Notice</h4>
          <p style="color: #a16207; font-size: 13px; margin: 0; line-height: 1.4;">
            • This link expires in ${RESET_TOKEN_EXPIRY_MINUTES} minutes<br>
            • Only works for your ${roleTitle} account<br>
            • If you didn't request this, ignore this email<br>
            • Your password won't change unless you click the link
          </p>
        </div>

        <div style="text-align: center; margin-top: 32px; padding-top: 24px; border-top: 1px solid #e5e7eb;">
          <p style="color: #9ca3af; font-size: 12px; margin: 0;">
            Need help? Contact us at <a href="mailto:support@tanadelivery.com" style="color: #CC1A1A;">support@tanadelivery.com</a>
          </p>
        </div>
      </div>

      <!-- Footer -->
      <div style="background: #f9fafb; padding: 20px 40px; text-align: center;">
        <p style="color: #6b7280; font-size: 12px; margin: 0;">
          © 2026 Tana Delivery. All rights reserved.<br>
          This email was sent because you requested a password reset for your ${roleTitle} account.
        </p>
      </div>
    </div>
    `
  );

  logger.info('Password reset email sent', { userId: user.id });
}

export async function resetPassword(token: string, newPassword: string): Promise<void> {
  const tokenHash = crypto.createHash('sha256').update(token).digest('hex');

  const result = await query<{ id: string; user_id: string; expires_at: Date; used: boolean }>(
    `SELECT * FROM password_reset_tokens
     WHERE token_hash = $1 AND used = FALSE AND expires_at > NOW()`,
    [tokenHash]
  );
  const record = result.rows[0];

  if (!record) {
    const err = new Error('Invalid or expired reset token') as Error & { statusCode: number };
    err.statusCode = 400;
    throw err;
  }

  const newHash = await bcrypt.hash(newPassword, BCRYPT_ROUNDS);

  await withTransaction(async (client) => {
    // Mark token used
    await client.query(
      'UPDATE password_reset_tokens SET used = TRUE WHERE id = $1',
      [record.id]
    );
    // Update password
    await client.query(
      'UPDATE users SET password_hash = $1, updated_at = NOW() WHERE id = $2',
      [newHash, record.user_id]
    );
    // Invalidate all active sessions for security
    await client.query(
      'DELETE FROM refresh_tokens WHERE user_id = $1',
      [record.user_id]
    );
  });

  logger.info('Password reset successfully', { userId: record.user_id });
}
// ── Google Sign-In ────────────────────────────────────────────────────────────

export async function googleSignIn(
  idToken: string,
  role: UserRole
): Promise<AuthResult> {
  const googleUser = await verifyGoogleIdToken(idToken);
  
  // Look for existing user by Google ID first, then by email
  let user = await query<User>(
    'SELECT * FROM users WHERE provider = $1 AND external_id = $2',
    ['google', googleUser.id]
  ).then(r => r.rows[0]);

  if (!user) {
    // Check if email exists with different provider
    const existingEmail = await query<User>(
      'SELECT * FROM users WHERE email = $1',
      [googleUser.email]
    );

    if (existingEmail.rows[0]) {
      const err = new Error(
        'An account with this email already exists. Please sign in with your email and password.'
      ) as Error & { statusCode: number };
      err.statusCode = 409;
      throw err;
    }

    // Create new Google user account
    const result = await query<User>(
      `INSERT INTO users (
        email, role, display_name, profile_photo_url, provider, external_id, 
        email_verified, status
      ) VALUES ($1, $2, $3, $4, $5, $6, TRUE, 'active') RETURNING *`,
      [
        googleUser.email,
        role,
        googleUser.name,
        googleUser.picture,
        'google',
        googleUser.id
      ]
    );
    user = result.rows[0];
    
    logger.info('New Google user registered', { 
      userId: user.id, 
      email: user.email, 
      role: user.role 
    });
  } else {
    // Existing Google user - update profile info in case it changed
    const updated = await query<User>(
      `UPDATE users SET 
        display_name = $1, 
        profile_photo_url = $2, 
        updated_at = NOW() 
       WHERE id = $3 RETURNING *`,
      [googleUser.name, googleUser.picture, user.id]
    );
    user = updated.rows[0];
    
    logger.info('Existing Google user signed in', { 
      userId: user.id, 
      email: user.email 
    });
  }

  if (user.status === 'suspended') {
    const err = new Error('Account suspended') as Error & { statusCode: number };
    err.statusCode = 401;
    throw err;
  }

  // Generate tokens
  const jwtToken = generateJwt(user.id, user.role);
  const { raw, hash } = generateRefreshToken();

  const expiresAt = new Date();
  expiresAt.setDate(expiresAt.getDate() + 7);

  // Delete all existing tokens for this user before inserting new one
  await query('DELETE FROM refresh_tokens WHERE user_id = $1', [user.id]);
  await query(
    'INSERT INTO refresh_tokens (user_id, token_hash, expires_at) VALUES ($1, $2, $3)',
    [user.id, hash, expiresAt]
  );

  return { user: toPublicUser(user), tokens: { jwt: jwtToken, refreshToken: raw } };
}