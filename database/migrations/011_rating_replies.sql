-- Migration 011: Rating Replies
-- Allows restaurant owners to publicly reply to customer reviews

ALTER TABLE ratings
  ADD COLUMN IF NOT EXISTS reply TEXT,
  ADD COLUMN IF NOT EXISTS replied_at TIMESTAMP;
