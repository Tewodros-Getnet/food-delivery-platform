import { Request, Response, NextFunction } from 'express';
import { errorResponse } from '../utils/response';

export function authorize(...roles: string[]) {
  return (req: Request, res: Response, next: NextFunction) => {
    if (!req.userRole || !roles.includes(req.userRole)) {
      res.status(403).json(errorResponse('Forbidden: insufficient permissions'));
      return;
    }
    next();
  };
}
