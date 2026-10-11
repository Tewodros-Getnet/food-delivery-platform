import { Router } from 'express';
import { redirectToApp } from '../controllers/redirect.controller';

const router = Router();

// Redirect route for password reset links
router.get('/', redirectToApp);

export default router;