import rateLimit from 'express-rate-limit';

// Global rate limiter: 100 requests per 15 minutes per IP
export const rateLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 100,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, data: null, error: 'Too many requests, please try again later.' },
});

// Stricter limiter for auth endpoints: 10 requests per 15 minutes per IP
export const authRateLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { success: false, data: null, error: 'Too many authentication attempts, please try again later.' },
});
