-- ================================================================
-- Messages Table Setup for CampusRide Chat Feature
-- Run this script in Supabase SQL Editor
-- ================================================================

-- Create messages table
CREATE TABLE IF NOT EXISTS messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ride_id UUID REFERENCES rides(id) ON DELETE CASCADE,
  from_user UUID REFERENCES profiles(id) ON DELETE CASCADE,
  to_user UUID REFERENCES profiles(id) ON DELETE CASCADE,
  message TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);

-- Create indexes for better query performance
CREATE INDEX IF NOT EXISTS idx_messages_ride_id ON messages(ride_id);
CREATE INDEX IF NOT EXISTS idx_messages_from_user ON messages(from_user);
CREATE INDEX IF NOT EXISTS idx_messages_to_user ON messages(to_user);
CREATE INDEX IF NOT EXISTS idx_messages_created_at ON messages(created_at);

-- Enable realtime for messages (required for subscribeMessages to work)
ALTER TABLE messages REPLICA IDENTITY FULL;

-- Enable Row Level Security
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist (for re-running script)
DROP POLICY IF EXISTS "Users can read their own messages" ON messages;
DROP POLICY IF EXISTS "Users can send messages" ON messages;

-- RLS Policy: Users can read messages they sent or received
CREATE POLICY "Users can read their own messages"
ON messages FOR SELECT
USING (auth.uid() = from_user OR auth.uid() = to_user);

-- RLS Policy: Users can insert messages where they are the sender
CREATE POLICY "Users can send messages"
ON messages FOR INSERT
WITH CHECK (auth.uid() = from_user);

-- Grant necessary permissions
GRANT SELECT, INSERT ON messages TO authenticated;

-- ================================================================
-- Compatibility: Normalize column names and types for messages
-- These blocks safely rename common alternate column names
-- and ensure UUID types + FKs expected by the app.
-- Run in Supabase SQL editor. Idempotent and safe to re-run.
-- ================================================================
DO $$
BEGIN
  -- Rename alternate sender/receiver columns
  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'messages' AND column_name = 'sender_id'
  ) THEN
    ALTER TABLE messages RENAME COLUMN sender_id TO from_user;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'messages' AND column_name = 'receiver_id'
  ) THEN
    ALTER TABLE messages RENAME COLUMN receiver_id TO to_user;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'messages' AND column_name = 'sender'
  ) THEN
    ALTER TABLE messages RENAME COLUMN sender TO from_user;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'messages' AND column_name = 'receiver'
  ) THEN
    ALTER TABLE messages RENAME COLUMN receiver TO to_user;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'messages' AND column_name = 'user_id'
  ) THEN
    ALTER TABLE messages RENAME COLUMN user_id TO from_user;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'messages' AND column_name = 'peer_id'
  ) THEN
    ALTER TABLE messages RENAME COLUMN peer_id TO to_user;
  END IF;

  -- Rename common camelCase variants
  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'messages' AND column_name = 'rideId'
  ) THEN
    ALTER TABLE messages RENAME COLUMN "rideId" TO ride_id;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'messages' AND column_name = 'fromUser'
  ) THEN
    ALTER TABLE messages RENAME COLUMN "fromUser" TO from_user;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'messages' AND column_name = 'toUser'
  ) THEN
    ALTER TABLE messages RENAME COLUMN "toUser" TO to_user;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'messages' AND column_name = 'createdAt'
  ) THEN
    ALTER TABLE messages RENAME COLUMN "createdAt" TO created_at;
  END IF;

  -- Rename common message content column variants
  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'messages' AND column_name = 'content'
  ) THEN
    ALTER TABLE messages RENAME COLUMN content TO message;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'messages' AND column_name = 'text'
  ) THEN
    ALTER TABLE messages RENAME COLUMN text TO message;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'messages' AND column_name = 'message_text'
  ) THEN
    ALTER TABLE messages RENAME COLUMN message_text TO message;
  END IF;
END
$$;

-- Ensure UUID types for foreign key columns
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'messages' AND column_name = 'ride_id' AND data_type IN ('text','character varying')
  ) THEN
    ALTER TABLE messages ALTER COLUMN ride_id TYPE uuid USING ride_id::uuid;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'messages' AND column_name = 'from_user' AND data_type IN ('text','character varying')
  ) THEN
    ALTER TABLE messages ALTER COLUMN from_user TYPE uuid USING from_user::uuid;
  END IF;

  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'messages' AND column_name = 'to_user' AND data_type IN ('text','character varying')
  ) THEN
    ALTER TABLE messages ALTER COLUMN to_user TYPE uuid USING to_user::uuid;
  END IF;
END
$$;

-- Ensure foreign keys exist (skip if already present)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conrelid = 'public.messages'::regclass AND conname = 'messages_ride_id_fkey'
  ) THEN
    ALTER TABLE messages
      ADD CONSTRAINT messages_ride_id_fkey
      FOREIGN KEY (ride_id) REFERENCES rides(id) ON DELETE CASCADE;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conrelid = 'public.messages'::regclass AND conname = 'messages_from_user_fkey'
  ) THEN
    ALTER TABLE messages
      ADD CONSTRAINT messages_from_user_fkey
      FOREIGN KEY (from_user) REFERENCES profiles(id) ON DELETE CASCADE;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint 
    WHERE conrelid = 'public.messages'::regclass AND conname = 'messages_to_user_fkey'
  ) THEN
    ALTER TABLE messages
      ADD CONSTRAINT messages_to_user_fkey
      FOREIGN KEY (to_user) REFERENCES profiles(id) ON DELETE CASCADE;
  END IF;
END
$$;

-- ================================================================
-- Verification: Check if table was created successfully
-- ================================================================
SELECT 
  table_name,
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_name = 'messages'
ORDER BY ordinal_position;
