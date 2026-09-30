-- Migration: Add Google Sign-In support
-- This adds OAuth provider support while maintaining backward compatibility

-- Add OAuth fields to users table
ALTER TABLE users 
ADD COLUMN external_id VARCHAR(255),
ADD COLUMN provider VARCHAR(50) DEFAULT 'email' NOT NULL;

-- Make password_hash optional for OAuth accounts
ALTER TABLE users 
ALTER COLUMN password_hash DROP NOT NULL;

-- Add constraints
ALTER TABLE users 
ADD CONSTRAINT chk_provider CHECK (provider IN ('email', 'google'));

-- Ensure external_id is required for OAuth providers
ALTER TABLE users 
ADD CONSTRAINT chk_oauth_external_id CHECK (
  (provider = 'email' AND external_id IS NULL) OR 
  (provider != 'email' AND external_id IS NOT NULL)
);

-- Ensure password_hash is required for email accounts
ALTER TABLE users 
ADD CONSTRAINT chk_email_password CHECK (
  (provider != 'email') OR 
  (provider = 'email' AND password_hash IS NOT NULL)
);

-- Unique constraint for OAuth accounts
CREATE UNIQUE INDEX idx_users_provider_external_id 
ON users(provider, external_id) 
WHERE provider != 'email';

-- For existing users, ensure they have email provider
UPDATE users SET provider = 'email' WHERE provider IS NULL;

-- Add index for OAuth lookups
CREATE INDEX idx_users_external_id ON users(external_id) WHERE external_id IS NOT NULL;