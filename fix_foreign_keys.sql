-- Fix foreign key relationships to reference profiles instead of auth.users

-- 1. Fix drivers table foreign key
ALTER TABLE drivers DROP CONSTRAINT IF EXISTS drivers_id_fkey;
ALTER TABLE drivers ADD CONSTRAINT drivers_id_fkey 
  FOREIGN KEY (id) REFERENCES profiles(id) ON DELETE CASCADE;

-- 2. Fix support_chats table foreign key
ALTER TABLE support_chats DROP CONSTRAINT IF EXISTS support_chats_user_id_fkey;
ALTER TABLE support_chats ADD CONSTRAINT support_chats_user_id_fkey 
  FOREIGN KEY (user_id) REFERENCES profiles(id) ON DELETE CASCADE;

-- Note: This will make Supabase PostgREST understand the relationships
-- between drivers->profiles and support_chats->profiles for embedded queries
