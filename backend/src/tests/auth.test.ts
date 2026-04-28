// Feature: food-delivery-app
// Property 1: Registration creates account with hashed password and tokens
// Property 2: Duplicate email registration rejected
// Property 3: Login with valid credentials returns tokens
// Property 4: Login with invalid credentials rejected
// Property 5: Refresh token exchange issues new JWT
// Property 6: Invalid refresh token rejected
// Property 7: Logout invalidates refresh token
// Property 8: Role-based access control enforced

import fc from 'fast-check';
import * as authService from '../services/auth.service';
import { pool } from '../config/database';
import { authenticate } from '../middleware/auth';
import { authorize } from '../middleware/rbac';
import { Request, Response } from 'express';

// Mock email service to avoid real SendGrid calls in tests
jest.mock('../services/email.service', () => ({
  sendOtpEmail: jest.fn().mockResolvedValue(undefined),
}));

beforeAll(async () => {
  // Clean up only test users created by this suite (no FK violations since we delete orders first)
  await pool.query(`DELETE FROM order_items WHERE order_id IN (
    SELECT id FROM orders WHERE customer_id IN (SELECT id FROM users WHERE email LIKE '%@test.com')
  )`);
  await pool.query(`DELETE FROM orders WHERE customer_id IN (SELECT id FROM users WHERE email LIKE '%@test.com')`);
  await pool.query(`DELETE FROM refresh_tokens WHERE user_id IN (SELECT id FROM users WHERE email LIKE '%@test.com')`);
  await pool.query(`DELETE FROM users WHERE email LIKE '%@test.com'`);
});

afterAll(async () => {
  await pool.query(`DELETE FROM order_items WHERE order_id IN (
    SELECT id FROM orders WHERE customer_id IN (SELECT id FROM users WHERE email LIKE '%@test.com')
  )`);
  await pool.query(`DELETE FROM orders WHERE customer_id IN (SELECT id FROM users WHERE email LIKE '%@test.com')`);
  await pool.query(`DELETE FROM refresh_tokens WHERE user_id IN (SELECT id FROM users WHERE email LIKE '%@test.com')`);
  await pool.query(`DELETE FROM users WHERE email LIKE '%@test.com'`);
  await pool.end();
});

/**
 * Helper: register a user and immediately verify their email so they can log in.
 * Returns the AuthResult (user + tokens) from login.
 */
async function registerAndVerify(
  email: string,
  password: string,
  role: 'customer' | 'rider' | 'restaurant'
): Promise<authService.AuthResult> {
  const reg = await authService.register(email, password, role);
  // Directly mark email as verified in DB (bypasses OTP flow for tests)
  await pool.query('UPDATE users SET email_verified = TRUE WHERE id = $1', [reg.userId]);
  return authService.login(email, password);
}

// ── Property 1 & 2: Registration ─────────────────────────────────────────────

describe('Property 1: Registration creates account with hashed password and tokens', () => {
  test('valid registration + verification returns jwt, refreshToken, and user without password_hash', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.emailAddress({ size: 'small' }),
        fc.constantFrom('customer' as const, 'rider' as const),
        async (email, role) => {
          const result = await registerAndVerify(email, 'Password123!', role);
          expect(result.tokens.jwt).toBeTruthy();
          expect(result.tokens.refreshToken).toBeTruthy();
          expect(result.user.email).toBe(email);
          expect(result.user.role).toBe(role);
          expect((result.user as unknown as Record<string, unknown>)['password_hash']).toBeUndefined();
          await pool.query('DELETE FROM users WHERE email = $1', [email]);
        }
      ),
      { numRuns: 10 }
    );
  });
});

describe('Property 2: Duplicate email registration rejected', () => {
  test('registering same email twice returns 409', async () => {
    const email = `dup_${Date.now()}@test.com`;
    await authService.register(email, 'Password123!', 'customer');
    // Mark verified so the second attempt hits the 409 path (not the resend-OTP path)
    await pool.query('UPDATE users SET email_verified = TRUE WHERE email = $1', [email]);

    await expect(
      authService.register(email, 'DifferentPass1!', 'rider')
    ).rejects.toMatchObject({ statusCode: 409 });

    await pool.query('DELETE FROM users WHERE email = $1', [email]);
  });
});

// ── Property 3 & 4: Login ────────────────────────────────────────────────────

describe('Property 3: Login with valid credentials returns tokens', () => {
  test('correct credentials return jwt and refreshToken', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.emailAddress({ size: 'small' }),
        async (email) => {
          await authService.register(email, 'Password123!', 'customer');
          await pool.query('UPDATE users SET email_verified = TRUE WHERE email = $1', [email]);
          const result = await authService.login(email, 'Password123!');
          expect(result.tokens.jwt).toBeTruthy();
          expect(result.tokens.refreshToken).toBeTruthy();
          await pool.query('DELETE FROM users WHERE email = $1', [email]);
        }
      ),
      { numRuns: 10 }
    );
  });
});

describe('Property 4: Login with invalid credentials rejected', () => {
  test('wrong password returns 401', async () => {
    const email = `inv_${Date.now()}@test.com`;
    await authService.register(email, 'Password123!', 'customer');
    await pool.query('UPDATE users SET email_verified = TRUE WHERE email = $1', [email]);

    await expect(authService.login(email, 'WrongPassword!')).rejects.toMatchObject({ statusCode: 401 });
    await pool.query('DELETE FROM users WHERE email = $1', [email]);
  });

  test('non-existent email returns 401', async () => {
    await expect(authService.login('nobody@nowhere.com', 'pass')).rejects.toMatchObject({ statusCode: 401 });
  });
});

// ── Property 5 & 6: Token Refresh ────────────────────────────────────────────

describe('Property 5: Refresh token exchange issues new JWT', () => {
  test('valid refresh token returns new jwt', async () => {
    const email = `ref_${Date.now()}@test.com`;
    const { tokens } = await registerAndVerify(email, 'Password123!', 'customer');
    const result = await authService.refresh(tokens.refreshToken);
    expect(result.jwt).toBeTruthy();
    await pool.query('DELETE FROM users WHERE email = $1', [email]);
  });
});

describe('Property 6: Invalid refresh token rejected', () => {
  test('random/expired token returns 401', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.uuid(),
        async (fakeToken) => {
          await expect(authService.refresh(fakeToken)).rejects.toMatchObject({ statusCode: 401 });
        }
      ),
      { numRuns: 10 }
    );
  });
});

// ── Property 7: Logout ───────────────────────────────────────────────────────

describe('Property 7: Logout invalidates refresh token', () => {
  test('after logout, refresh token cannot be reused', async () => {
    const email = `logout_${Date.now()}@test.com`;
    const { tokens } = await registerAndVerify(email, 'Password123!', 'customer');
    await authService.logout(tokens.refreshToken);
    await expect(authService.refresh(tokens.refreshToken)).rejects.toMatchObject({ statusCode: 401 });
    await pool.query('DELETE FROM users WHERE email = $1', [email]);
  });
});

// ── Property 8: RBAC ─────────────────────────────────────────────────────────

describe('Property 8: Role-based access control enforced', () => {
  function mockReqWithRole(role: string | undefined): Partial<Request> {
    return { userRole: role } as Partial<Request>;
  }

  function mockRes(): { status: jest.Mock; json: jest.Mock } {
    const res = { status: jest.fn().mockReturnThis(), json: jest.fn() };
    return res;
  }

  test('user with correct role passes through', () => {
    const middleware = authorize('admin');
    const req = mockReqWithRole('admin') as Request;
    const res = mockRes() as unknown as Response;
    const next = jest.fn();
    middleware(req, res, next);
    expect(next).toHaveBeenCalled();
    expect(res.status).not.toHaveBeenCalled();
  });

  test('user with wrong role gets 403', () => {
    const middleware = authorize('admin');
    const req = mockReqWithRole('customer') as Request;
    const res = mockRes() as unknown as Response;
    const next = jest.fn();
    middleware(req, res, next);
    expect(res.status).toHaveBeenCalledWith(403);
    expect(next).not.toHaveBeenCalled();
  });

  test('unauthenticated request gets 401 from authenticate middleware', () => {
    const req = { headers: {} } as Request;
    const res = mockRes() as unknown as Response;
    const next = jest.fn();
    authenticate(req, res, next);
    expect(res.status).toHaveBeenCalledWith(401);
    expect(next).not.toHaveBeenCalled();
  });
});
