import { Router } from 'express';
import {
  registerHandler, registerValidation,
  loginHandler, loginValidation,
  refreshHandler, refreshValidation,
  logoutHandler, logoutValidation,
  verifyOtpHandler, verifyOtpValidation,
  resendOtpHandler, resendOtpValidation,
  requestPasswordResetHandler, requestPasswordResetValidation,
  resetPasswordHandler, resetPasswordValidation,
} from '../controllers/auth.controller';

const router = Router();

router.post('/register', registerValidation, registerHandler);
router.post('/verify-otp', verifyOtpValidation, verifyOtpHandler);
router.post('/resend-otp', resendOtpValidation, resendOtpHandler);
router.post('/login', loginValidation, loginHandler);
router.post('/refresh', refreshValidation, refreshHandler);
router.post('/logout', logoutValidation, logoutHandler);
// Step 1: user submits email → receives reset link
router.post('/request-password-reset', requestPasswordResetValidation, requestPasswordResetHandler);
// Step 2: user submits token from link + new password
router.post('/reset-password', resetPasswordValidation, resetPasswordHandler);

export default router;
