import { Router, Request, Response, NextFunction } from 'express';
import { body } from 'express-validator';
import { authenticate } from '../middleware/auth';
import { validate } from '../middleware/validate';
import { query, withTransaction } from '../config/database';
import { uploadImage } from '../services/cloudinary.service';
import { registerFcmToken } from '../services/fcm.service';
import { getRiderRatings } from '../services/rating.service';
import bcrypt from 'bcrypt';
import { successResponse, errorResponse } from '../utils/response';

const router = Router();

// GET /users/profile
router.get('/profile', authenticate, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const result = await query(
      'SELECT id, email, role, display_name, phone, profile_photo_url, status, created_at FROM users WHERE id = $1',
      [req.userId]
    );
    if (!result.rows[0]) { res.status(404).json(errorResponse('User not found')); return; }
    res.json(successResponse(result.rows[0]));
  } catch (err) { next(err); }
});

// PUT /users/profile
router.put('/profile', authenticate, [
  body('displayName').optional().trim(),
  body('phone').optional().matches(/^\+?[0-9]{7,15}$/).withMessage('Invalid phone number format'),
  validate,
], async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { displayName, phone, photoBase64 } = req.body as { displayName?: string; phone?: string; photoBase64?: string };
    let profile_photo_url: string | undefined;

    if (photoBase64) {
      profile_photo_url = await uploadImage(photoBase64, 'profiles');
    }

    const fields: string[] = [];
    const values: unknown[] = [];
    let idx = 1;

    if (displayName !== undefined) { fields.push(`display_name = $${idx++}`); values.push(displayName); }
    if (phone !== undefined) { fields.push(`phone = $${idx++}`); values.push(phone); }
    if (profile_photo_url !== undefined) { fields.push(`profile_photo_url = $${idx++}`); values.push(profile_photo_url); }
    fields.push(`updated_at = NOW()`);
    values.push(req.userId);

    const result = await query(
      `UPDATE users SET ${fields.join(', ')} WHERE id = $${idx}
       RETURNING id, email, role, display_name, phone, profile_photo_url, status`,
      values
    );
    res.json(successResponse(result.rows[0]));
  } catch (err) { next(err); }
});

// PUT /users/password
router.put('/password', authenticate, [
  body('currentPassword').notEmpty(),
  body('newPassword').isLength({ min: 8 }),
  validate,
], async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { currentPassword, newPassword } = req.body as { currentPassword: string; newPassword: string };
    const result = await query<{ password_hash: string }>('SELECT password_hash FROM users WHERE id = $1', [req.userId]);
    const user = result.rows[0];
    if (!user) { res.status(404).json(errorResponse('User not found')); return; }

    const valid = await bcrypt.compare(currentPassword, user.password_hash);
    if (!valid) { res.status(401).json(errorResponse('Current password is incorrect')); return; }

    const newHash = await bcrypt.hash(newPassword, 10);
    await query('UPDATE users SET password_hash = $1, updated_at = NOW() WHERE id = $2', [newHash, req.userId]);
    res.json(successResponse({ message: 'Password updated' }));
  } catch (err) { next(err); }
});

// POST /users/addresses
router.post('/addresses', authenticate, [
  body('addressLine').notEmpty().trim(),
  body('latitude').isFloat({ min: -90, max: 90 }),
  body('longitude').isFloat({ min: -180, max: 180 }),
  body('label').optional().trim(),
  body('isDefault').optional().isBoolean(),
  validate,
], async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { addressLine, latitude, longitude, label, isDefault } = req.body as {
      addressLine: string; latitude: number; longitude: number; label?: string; isDefault?: boolean;
    };
    await withTransaction(async (client) => {
      if (isDefault) {
        await client.query('UPDATE addresses SET is_default = FALSE WHERE user_id = $1', [req.userId]);
      }
      const result = await client.query(
        `INSERT INTO addresses (user_id, address_line, latitude, longitude, label, is_default)
         VALUES ($1,$2,$3,$4,$5,$6) RETURNING *`,
        [req.userId, addressLine, latitude, longitude, label ?? null, isDefault ?? false]
      );
      res.status(201).json(successResponse(result.rows[0]));
    });
  } catch (err) { next(err); }
});

// GET /users/addresses
router.get('/addresses', authenticate, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const result = await query('SELECT * FROM addresses WHERE user_id = $1 ORDER BY is_default DESC', [req.userId]);
    res.json(successResponse(result.rows));
  } catch (err) { next(err); }
});

// PUT /users/addresses/:id
router.put('/addresses/:id', authenticate, [
  body('addressLine').optional().trim().notEmpty(),
  body('label').optional().trim(),
  validate,
], async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { addressLine, label } = req.body as { addressLine?: string; label?: string };
    const fields: string[] = [];
    const values: unknown[] = [];
    let idx = 1;
    if (addressLine !== undefined) { fields.push(`address_line = $${idx++}`); values.push(addressLine); }
    if (label !== undefined) { fields.push(`label = $${idx++}`); values.push(label); }
    if (fields.length === 0) { res.status(422).json(errorResponse('Nothing to update')); return; }
    values.push(req.params.id, req.userId);
    const result = await query(
      `UPDATE addresses SET ${fields.join(', ')} WHERE id = $${idx} AND user_id = $${idx + 1} RETURNING *`,
      values
    );
    if (!result.rows[0]) { res.status(404).json(errorResponse('Address not found')); return; }
    res.json(successResponse(result.rows[0]));
  } catch (err) { next(err); }
});

// PUT /users/addresses/:id/default
router.put('/addresses/:id/default', authenticate, async (req: Request, res: Response, next: NextFunction) => {
  try {
    await withTransaction(async (client) => {
      await client.query('UPDATE addresses SET is_default = FALSE WHERE user_id = $1', [req.userId]);
      const result = await client.query(
        'UPDATE addresses SET is_default = TRUE WHERE id = $1 AND user_id = $2 RETURNING *',
        [req.params.id, req.userId]
      );
      if (!result.rows[0]) {
        const err = new Error('Address not found') as Error & { statusCode: number };
        err.statusCode = 404;
        throw err;
      }
      res.json(successResponse(result.rows[0]));
    });
  } catch (err) { next(err); }
});

// DELETE /users/addresses/:id
router.delete('/addresses/:id', authenticate, async (req: Request, res: Response, next: NextFunction) => {
  try {
    const result = await query(
      'DELETE FROM addresses WHERE id = $1 AND user_id = $2 RETURNING id',
      [req.params.id, req.userId]
    );
    if (!result.rows[0]) { res.status(404).json(errorResponse('Address not found')); return; }
    res.json(successResponse({ message: 'Address deleted' }));
  } catch (err) { next(err); }
});

// POST /users/fcm-token
router.post('/fcm-token', authenticate, [
  body('token').notEmpty(),
  body('deviceType').isIn(['ios', 'android', 'web']),
  validate,
], async (req: Request, res: Response, next: NextFunction) => {
  try {
    await registerFcmToken(req.userId!, req.body.token as string, req.body.deviceType as 'ios' | 'android' | 'web');
    res.json(successResponse({ message: 'FCM token registered' }));
  } catch (err) { next(err); }
});

// GET /users/riders/:id/ratings
router.get('/riders/:id/ratings', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const ratings = await getRiderRatings(req.params.id);
    res.json(successResponse(ratings));
  } catch (err) { next(err); }
});

export default router;
