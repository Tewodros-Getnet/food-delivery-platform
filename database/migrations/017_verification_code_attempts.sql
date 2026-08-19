-- Track wrong OTP attempts per code to enforce a max attempt limit
ALTER TABLE verification_codes
  ADD COLUMN IF NOT EXISTS attempts INT NOT NULL DEFAULT 0;
