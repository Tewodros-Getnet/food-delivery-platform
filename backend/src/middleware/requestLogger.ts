import { Request, Response, NextFunction } from 'express';
import { logger } from '../utils/logger';

export function requestLogger(req: Request, res: Response, next: NextFunction) {
  const start = Date.now();
  res.on('finish', () => {
    const ms = Date.now() - start;
    logger.info(`${req.method} ${req.path} → ${res.statusCode} in ${ms}ms`, {
      method: req.method,
      path: req.path,
      statusCode: res.statusCode,
      durationMs: ms,
    });
  });
  next();
}
