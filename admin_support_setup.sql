-- Admin support chat tables and setup

-- Create support_chats table
CREATE TABLE IF NOT EXISTS support_chats (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  subject TEXT,
  status TEXT DEFAULT 'open' CHECK (status IN ('open', 'in_progress', 'resolved', 'closed')),
  last_message TEXT,
  has_unread_admin BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create support_messages table
CREATE TABLE IF NOT EXISTS support_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  chat_id UUID NOT NULL REFERENCES support_chats(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  message TEXT NOT NULL,
  is_admin BOOLEAN DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_support_chats_user_id ON support_chats(user_id);
CREATE INDEX IF NOT EXISTS idx_support_chats_status ON support_chats(status);
CREATE INDEX IF NOT EXISTS idx_support_chats_updated_at ON support_chats(updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_support_messages_chat_id ON support_messages(chat_id);
CREATE INDEX IF NOT EXISTS idx_support_messages_created_at ON support_messages(created_at DESC);

-- Enable RLS
ALTER TABLE support_chats ENABLE ROW LEVEL SECURITY;
ALTER TABLE support_messages ENABLE ROW LEVEL SECURITY;

-- Enable Realtime replication for these tables (idempotent)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'support_chats'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE support_chats;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables 
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'support_messages'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE support_messages;
  END IF;
END $$;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Users can view their own chats" ON support_chats;
DROP POLICY IF EXISTS "Users can create their own chats" ON support_chats;
DROP POLICY IF EXISTS "Users can update their own chats" ON support_chats;
DROP POLICY IF EXISTS "Admins can view all chats" ON support_chats;
DROP POLICY IF EXISTS "Admins can update all chats" ON support_chats;
DROP POLICY IF EXISTS "Users can view messages in their chats" ON support_messages;
DROP POLICY IF EXISTS "Users can create messages in their chats" ON support_messages;
DROP POLICY IF EXISTS "Admins can view all messages" ON support_messages;
DROP POLICY IF EXISTS "Admins can create messages in all chats" ON support_messages;

-- RLS Policies for support_chats
CREATE POLICY "Users can view their own chats"
ON support_chats FOR SELECT
USING (user_id = auth.uid());

CREATE POLICY "Users can create their own chats"
ON support_chats FOR INSERT
WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can update their own chats"
ON support_chats FOR UPDATE
USING (user_id = auth.uid());

CREATE POLICY "Admins can view all chats"
ON support_chats FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM profiles 
    WHERE profiles.id = auth.uid() 
    AND profiles.role = 'admin'
  )
);

CREATE POLICY "Admins can update all chats"
ON support_chats FOR UPDATE
USING (
  EXISTS (
    SELECT 1 FROM profiles 
    WHERE profiles.id = auth.uid() 
    AND profiles.role = 'admin'
  )
);

-- RLS Policies for support_messages
CREATE POLICY "Users can view messages in their chats"
ON support_messages FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM support_chats 
    WHERE support_chats.id = support_messages.chat_id 
    AND support_chats.user_id = auth.uid()
  )
);

CREATE POLICY "Users can create messages in their chats"
ON support_messages FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1 FROM support_chats 
    WHERE support_chats.id = chat_id 
    AND support_chats.user_id = auth.uid()
  )
);

CREATE POLICY "Admins can view all messages"
ON support_messages FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM profiles 
    WHERE profiles.id = auth.uid() 
    AND profiles.role = 'admin'
  )
);

CREATE POLICY "Admins can create messages in all chats"
ON support_messages FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1 FROM profiles 
    WHERE profiles.id = auth.uid() 
    AND profiles.role = 'admin'
  )
);

-- Function to update chat's updated_at timestamp
CREATE OR REPLACE FUNCTION update_support_chat_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE support_chats 
  SET updated_at = NOW(),
      last_message = NEW.message
  WHERE id = NEW.chat_id;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to update chat timestamp on new message
DROP TRIGGER IF EXISTS trigger_update_support_chat_timestamp ON support_messages;
CREATE TRIGGER trigger_update_support_chat_timestamp
AFTER INSERT ON support_messages
FOR EACH ROW
EXECUTE FUNCTION update_support_chat_timestamp();
