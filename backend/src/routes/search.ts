import { Router, Request, Response, NextFunction } from 'express';
import { query } from '../config/database';
import { successResponse } from '../utils/response';

const router = Router();

router.get('/', async (req: Request, res: Response, next: NextFunction) => {
  try {
    const { q, page, limit } = req.query as Record<string, string>;
    if (!q) { res.json(successResponse({ restaurants: [], menuItems: [], total: 0 })); return; }

    const pageNum = parseInt(page ?? '1', 10);
    const limitNum = parseInt(limit ?? '20', 10);
    const offset = (pageNum - 1) * limitNum;
    const search = `%${q}%`;

    const [restaurants, menuItems] = await Promise.all([
      query(
        `SELECT * FROM restaurants
         WHERE status = 'approved' AND (name ILIKE $1 OR description ILIKE $1)
         ORDER BY average_rating DESC LIMIT $2 OFFSET $3`,
        [search, limitNum, offset]
      ),
      query(
        `SELECT mi.* FROM menu_items mi
         JOIN restaurants r ON r.id = mi.restaurant_id
         WHERE r.status = 'approved' AND mi.available = TRUE
         AND (mi.name ILIKE $1 OR mi.description ILIKE $1)
         LIMIT $2 OFFSET $3`,
        [search, limitNum, offset]
      ),
    ]);

    res.json(successResponse({
      restaurants: restaurants.rows,
      menuItems: menuItems.rows,
    }));
  } catch (err) { next(err); }
});

export default router;
