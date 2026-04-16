import { Router } from 'express';
import {
  registerHandler, registerValidation,
  loginHandler, loginValidation,
  refreshHandler, refreshValidation,
  logoutHandler, logoutValidation,
  verifyOtpHandler,
  resendOtpHandler,
} from '../controllers/auth.controller';

const router = Router();

router.post('/register', registerValidation, registerHandler);
router.post('/verify-otp', verifyOtpHandler);
router.post('/resend-otp', resendOtpHandler);
router.post('/login', loginValidation, loginHandler);
router.post('/refresh', refreshValidation, refreshHandler);
router.post('/logout', logoutValidation, logoutHandler);

export default router;
