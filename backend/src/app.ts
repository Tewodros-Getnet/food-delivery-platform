import express from 'express';
import cors from 'cors';
import { env } from './config/env';
import { requestIdMiddleware } from './middleware/requestId';
import { requestLogger } from './middleware/requestLogger';
import { rateLimiter, authRateLimiter } from './middleware/rateLimiter';
import { errorHandler, notFoundHandler } from './middleware/errorHandler';
import router from './routes/index';

const app = express();

const allowedOrigins = env.ALLOWED_ORIGINS.split(',').map(o => o.trim());

app.use(cors({
  origin: (origin, callback) => {
    // Allow requests with no origin (e.g. mobile apps, curl, server-to-server)
    if (!origin) return callback(null, true);
    if (allowedOrigins.includes(origin)) return callback(null, true);
    callback(new Error(`CORS: origin ${origin} not allowed`));
  },
  credentials: true,
}));

// Apply JSON body parser to everything EXCEPT the Chapa webhook
// (webhook needs raw body for HMAC signature verification)
app.use((req, res, next) => {
  if (req.path === '/api/v1/payments/webhook') return next();
  express.json({ limit: '10mb' })(req, res, next);
});
app.use((req, res, next) => {
  if (req.path === '/api/v1/payments/webhook') return next();
  express.urlencoded({ extended: true, limit: '10mb' })(req, res, next);
});
app.use(requestIdMiddleware);
app.use(requestLogger);
app.use(rateLimiter);

app.get('/health', (_req, res) => {
  res.json({ success: true, data: { status: 'ok' }, error: null });
});

app.use('/api/v1/auth', authRateLimiter);
app.use('/api/v1', router);

app.use(notFoundHandler);
app.use(errorHandler);

export default app;
