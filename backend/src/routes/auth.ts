import { Router } from 'express';
import {
  registerHandler, registerValidation,
  loginHandler, loginValidation,
  refreshHandler, refreshValidation,
  logoutHandler, logoutValidation,
  verifyOtpHandler,
  resendOtpHandler,
  resetPasswordHandler, resetPasswordValidation,
} from '../controllers/auth.controller';

const router = Router();

router.post('/register', registerValidation, registerHandler);
router.post('/verify-otp', verifyOtpHandler);
router.post('/resend-otp', resendOtpHandler);
router.post('/login', loginValidation, loginHandler);
router.post('/refresh', refreshValidation, refreshHandler);
router.post('/logout', logoutValidation, logoutHandler);
router.post('/reset-password', resetPasswordValidation, resetPasswordHandler);

export default router;
