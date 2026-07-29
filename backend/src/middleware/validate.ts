import { Request, Response, NextFunction } from 'express';
import { validationResult } from 'express-validator';
import { errorResponse } from '../utils/response';

export function validate(req: Request, res: Response, next: NextFunction) {
  const errors = validationResult(req);
  if (!errors.isEmpty()) {
    res.status(422).json({
      ...errorResponse('Validation failed'),
      details: errors.array().map((e) => ({ field: e.type === 'field' ? (e as { path: string }).path : 'unknown', message: e.msg })),
    });
    return;
  }
  next();
}
