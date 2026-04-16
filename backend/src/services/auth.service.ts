import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import crypto from 'crypto';
import { v4 as uuidv4 } from 'uuid';
import { query, withTransaction } from '../config/database';
import { env } from '../config/env';
import { User, PublicUser, UserRole } from '../models/user.model';
import { sendOtpEmail } from './email.service';

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
    created_at: user.created_at,
  };
}

function generateOtp(): string {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

async function storeAndSendOtp(userId: string, email: string): Promise<void> {
  const otp = generateOtp();
  const expiresAt = new Date(Date.now() + OTP_EXPIRY_MINUTES * 60 * 1000);
  // Invalidate any previous unused codes
  await query('UPDATE verification_codes SET used = TRUE WHERE user_id = $1 AND used = FALSE', [userId]);
  await query(
    'INSERT INTO verification_codes (user_id, code, expires_at) VALUES ($1, $2, $3)',
    [userId, otp, expiresAt]
  );
  await sendOtpEmail(email, otp);
}

export async function register(
  email: string,
  password: string,
  role: UserRole
): Promise<{ userId: string; email: string; pendingVerification: true }> {
  return withTransaction(async (client) => {
    const existing = await client.query(
      'SELECT id, email_verified FROM users WHERE email = $1',
      [email]
    );
    if (existing.rowCount && existing.rowCount > 0) {
      const existingUser = existing.rows[0] as { id: string; email_verified: boolean };
      // If registered but not verified, resend OTP
      if (!existingUser.email_verified) {
        await storeAndSendOtp(existingUser.id, email);
        return { userId: existingUser.id, email, pendingVerification: true };
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
    await storeAndSendOtp(user.id, email);
    return { userId: user.id, email, pendingVerification: true };
  });
}

export async function verifyOtp(userId: string, code: string): Promise<AuthResult> {
  const result = await query<{ id: string; code: string; expires_at: Date; used: boolean }>(
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
    const err = new Error('Verification code has expired') as Error & { statusCode: number };
    err.statusCode = 400;
    throw err;
  }
  if (record.code !== code) {
    const err = new Error('Invalid verification code') as Error & { statusCode: number };
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
  await query(
    'INSERT INTO refresh_tokens (user_id, token_hash, expires_at) VALUES ($1, $2, $3)',
    [user.id, hash, expiresAt]
  );

  return { user: toPublicUser(user), tokens: { jwt: jwtToken, refreshToken: raw } };
}

export async function resendOtp(userId: string): Promise<void> {
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
  await storeAndSendOtp(userId, user.email);
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

  const valid = await bcrypt.compare(password, user.password_hash);
  if (!valid) throw unauthorized;

  const jwtToken = generateJwt(user.id, user.role);
  const { raw, hash } = generateRefreshToken();

  const expiresAt = new Date();
  expiresAt.setDate(expiresAt.getDate() + 7);

  await query(
    `INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
     VALUES ($1, $2, $3)`,
    [user.id, hash, expiresAt]
  );

  return { user: toPublicUser(user), tokens: { jwt: jwtToken, refreshToken: raw } };
}

export async function refresh(rawToken: string): Promise<{ jwt: string }> {
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

  const { user_id, role, status } = result.rows[0] as { user_id: string; role: string; status: string };

  if (status === 'suspended') {
    const err = new Error('Account suspended') as Error & { statusCode: number };
    err.statusCode = 401;
    throw err;
  }

  return { jwt: generateJwt(user_id, role) };
}

export async function logout(rawToken: string): Promise<void> {
  const hash = crypto.createHash('sha256').update(rawToken).digest('hex');
  await query('DELETE FROM refresh_tokens WHERE token_hash = $1', [hash]);
}
