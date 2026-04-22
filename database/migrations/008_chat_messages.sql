-- Migration 008: Chat Messages
-- Adds in-app chat between customers and riders for active deliveries

CREATE TABLE chat_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES users(id),
  message TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE INDEX idx_chat_messages_order_id ON chat_messages(order_id);
CREATE INDEX idx_chat_messages_created_at ON chat_messages(created_at);
