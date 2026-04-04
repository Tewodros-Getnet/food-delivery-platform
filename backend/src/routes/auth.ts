import { Router } from 'express';
import {
  registerHandler, registerValidation,
  loginHandler, loginValidation,
  refreshHandler, refreshValidation,
  logoutHandler, logoutValidation,
} from '../controllers/auth.controller';

const router = Router();

router.post('/register', registerValidation, registerHandler);
router.post('/login', loginValidation, loginHandler);
router.post('/refresh', refreshValidation, refreshHandler);
router.post('/logout', logoutValidation, logoutHandler);

export default router;
