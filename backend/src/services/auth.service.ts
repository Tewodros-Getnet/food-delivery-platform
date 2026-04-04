import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import crypto from 'crypto';
import { v4 as uuidv4 } from 'uuid';
import { query, withTransaction } from '../config/database';
import { env } from '../config/env';
import { User, PublicUser, UserRole } from '../models/user.model';

const BCRYPT_ROUNDS = 10;

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

export async function register(
  email: string,
  password: string,
  role: UserRole
): Promise<AuthResult> {
  return withTransaction(async (client) => {
    // Check duplicate email
    const existing = await client.query(
      'SELECT id FROM users WHERE email = $1',
      [email]
    );
    if (existing.rowCount && existing.rowCount > 0) {
      const err = new Error('Email already registered') as Error & { statusCode: number };
      err.statusCode = 409;
      throw err;
    }

    const password_hash = await bcrypt.hash(password, BCRYPT_ROUNDS);

    const result = await client.query<User>(
      `INSERT INTO users (email, password_hash, role)
       VALUES ($1, $2, $3)
       RETURNING *`,
      [email, password_hash, role]
    );
    const user = result.rows[0];

    const jwtToken = generateJwt(user.id, user.role);
    const { raw, hash } = generateRefreshToken();

    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + 7);

    await client.query(
      `INSERT INTO refresh_tokens (user_id, token_hash, expires_at)
       VALUES ($1, $2, $3)`,
      [user.id, hash, expiresAt]
    );

    return { user: toPublicUser(user), tokens: { jwt: jwtToken, refreshToken: raw } };
  });
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
