import { Request, Response, NextFunction } from 'express';
import { logger } from '../utils/logger';
import { errorResponse } from '../utils/response';

export interface AppError extends Error {
  statusCode?: number;
}

export function errorHandler(
  err: AppError,
  req: Request,
  res: Response,
  _next: NextFunction
) {
  const statusCode = err.statusCode || 500;
  const message = statusCode === 500 ? 'Internal server error' : err.message;

  logger.error(err.message, {
    requestId: req.requestId,
    userId: req.userId,
    method: req.method,
    path: req.path,
    statusCode,
    stack: err.stack,
  });

  res.status(statusCode).json(errorResponse(message));
}

export function notFoundHandler(req: Request, res: Response) {
  res.status(404).json(errorResponse(`Resource not found: ${req.path}`));
}
