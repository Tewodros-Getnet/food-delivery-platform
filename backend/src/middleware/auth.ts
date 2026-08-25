import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { env } from '../config/env';
import { errorResponse } from '../utils/response';

interface JwtPayload {
  userId: string;
  role: string;
}

export function authenticate(req: Request, res: Response, next: NextFunction) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    res.status(401).json(errorResponse('Authentication required'));
    return;
  }

  const token = authHeader.split(' ')[1];
  try {
    const payload = jwt.verify(token, env.JWT_SECRET) as JwtPayload;
    req.userId = payload.userId;
    req.userRole = payload.role;
    next();
  } catch {
    res.status(401).json(errorResponse('Invalid or expired token'));
  }
}

/**
 * Like `authenticate` but never rejects the request.
 * If a valid Bearer token is present, req.userId and req.userRole are set.
 * If no token (or an invalid one) is present, the request continues as an
 * anonymous/guest request with req.userId undefined.
 *
 * Use this on public endpoints that behave differently when a user is logged in
 * — e.g. the menu list endpoint, which returns all items for the restaurant
 * owner but only available items for customers/guests.
 */
export function optionalAuthenticate(req: Request, _res: Response, next: NextFunction) {
  const authHeader = req.headers.authorization;
  if (authHeader?.startsWith('Bearer ')) {
    const token = authHeader.split(' ')[1];
    try {
      const payload = jwt.verify(token, env.JWT_SECRET) as JwtPayload;
      req.userId   = payload.userId;
      req.userRole = payload.role;
    } catch {
      // Invalid / expired token — treat as unauthenticated, not an error
    }
  }
  next();
}
