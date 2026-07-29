import { Request, Response, NextFunction } from 'express';
import { body } from 'express-validator';
import { validate } from '../middleware/validate';
import * as authService from '../services/auth.service';
import { successResponse } from '../utils/response';

export const registerValidation = [
  body('email').isEmail().normalizeEmail(),
  body('password').isLength({ min: 8 }).withMessage('Password must be at least 8 characters'),
  body('role').isIn(['customer', 'restaurant', 'rider']).withMessage('Invalid role'),
  validate,
];

export const loginValidation = [
  body('email').isEmail().normalizeEmail(),
  body('password').notEmpty(),
  validate,
];

export const refreshValidation = [
  body('refreshToken').notEmpty().withMessage('Refresh token required'),
  validate,
];

export const logoutValidation = [
  body('refreshToken').notEmpty().withMessage('Refresh token required'),
  validate,
];

// Fix #3: validate userId (must be a UUID) and code (must be 6 digits)
export const verifyOtpValidation = [
  body('userId').isUUID().withMessage('userId must be a valid UUID'),
  body('code')
    .isString()
    .matches(/^\d{6}$/)
    .withMessage('code must be a 6-digit number'),
  validate,
];

// Fix #3: validate userId on resend
export const resendOtpValidation = [
  body('userId').isUUID().withMessage('userId must be a valid UUID'),
  validate,
];

// Fix #1: validation for password reset request
export const requestPasswordResetValidation = [
  body('email').isEmail().normalizeEmail().withMessage('A valid email is required'),
  validate,
];

// Fix #1: validation for password reset confirmation
export const resetPasswordValidation = [
  body('token').notEmpty().withMessage('Reset token is required'),
  body('newPassword')
    .isLength({ min: 8 })
    .withMessage('New password must be at least 8 characters'),
  validate,
];

export async function registerHandler(req: Request, res: Response, next: NextFunction) {
  try {
    const { email, password, role } = req.body as { email: string; password: string; role: 'customer' | 'restaurant' | 'rider' };
    const result = await authService.register(email, password, role);
    res.status(201).json(successResponse(result));
  } catch (err) {
    next(err);
  }
}

export async function verifyOtpHandler(req: Request, res: Response, next: NextFunction) {
  try {
    const { userId, code } = req.body as { userId: string; code: string };
    const result = await authService.verifyOtp(userId, code);
    res.json(successResponse(result));
  } catch (err) {
    next(err);
  }
}

export async function resendOtpHandler(req: Request, res: Response, next: NextFunction) {
  try {
    const { userId } = req.body as { userId: string };
    await authService.resendOtp(userId);
    res.json(successResponse({ message: 'OTP resent' }));
  } catch (err) {
    next(err);
  }
}

export async function loginHandler(req: Request, res: Response, next: NextFunction) {
  try {
    const { email, password } = req.body as { email: string; password: string };
    const result = await authService.login(email, password);
    res.json(successResponse(result));
  } catch (err) {
    next(err);
  }
}

export async function refreshHandler(req: Request, res: Response, next: NextFunction) {
  try {
    const { refreshToken } = req.body as { refreshToken: string };
    const result = await authService.refresh(refreshToken);
    res.json(successResponse(result));
  } catch (err) {
    next(err);
  }
}

export async function logoutHandler(req: Request, res: Response, next: NextFunction) {
  try {
    const { refreshToken } = req.body as { refreshToken: string };
    await authService.logout(refreshToken);
    res.json(successResponse({ message: 'Logged out successfully' }));
  } catch (err) {
    next(err);
  }
}

// Fix #1: request a password reset link via email
export async function requestPasswordResetHandler(req: Request, res: Response, next: NextFunction) {
  try {
    const { email } = req.body as { email: string };
    await authService.requestPasswordReset(email);
    // Always return success — never leak whether the email exists
    res.json(successResponse({ message: 'If that email is registered you will receive a reset link shortly' }));
  } catch (err) {
    next(err);
  }
}

// Fix #1: confirm the reset using the token from the email link
export async function resetPasswordHandler(req: Request, res: Response, next: NextFunction) {
  try {
    const { token, newPassword } = req.body as { token: string; newPassword: string };
    await authService.resetPassword(token, newPassword);
    res.json(successResponse({ message: 'Password reset successfully. Please log in with your new password.' }));
  } catch (err) {
    next(err);
  }
}
