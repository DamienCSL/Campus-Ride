-- ========================================
-- AVATARS STORAGE BUCKET - RLS POLICIES
-- ========================================
-- 
-- ⚠️  DO NOT run this in SQL Editor! 
-- Instead, use the Supabase Dashboard UI to create these policies.
--
-- Follow these steps:
--
-- STEP 1: Go to Storage in your Supabase Dashboard
-- STEP 2: Select the "avatars" bucket (or create it if it doesn't exist)
-- STEP 3: Go to the "Policies" tab
-- STEP 4: Click "New Policy" for each policy below
--
-- ========================================

-- POLICY 1: Allow authenticated users to INSERT (upload)
-- ========================================
-- Policy Name: Users can upload their own avatar
-- Allowed operation: INSERT
-- Target roles: authenticated
-- Policy definition (WITH CHECK):

(bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text)

-- ========================================

-- POLICY 2: Allow authenticated users to UPDATE
-- ========================================
-- Policy Name: Users can update their own avatar
-- Allowed operation: UPDATE
-- Target roles: authenticated
-- USING expression:

(bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text)

-- WITH CHECK expression:

(bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text)

-- ========================================

-- POLICY 3: Allow authenticated users to DELETE
-- ========================================
-- Policy Name:     
-- Allowed operation: DELETE
-- Target roles: authenticated
-- USING expression:

(bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text)

-- ========================================

-- POLICY 4: Allow public to SELECT (view)
-- ========================================
-- Policy Name: Anyone can view avatars
-- Allowed operation: SELECT
-- Target roles: public
-- USING expression:

(bucket_id = 'avatars')

-- ========================================
-- ALTERNATIVE: Simple Policy (if above doesn't work)
-- ========================================
-- If the folder-based policy doesn't work, use this simpler approach:
-- This allows any authenticated user to upload/update/delete any file in avatars bucket
-- (Less secure but easier to set up for testing)
--
-- Policy Name: Authenticated users full access
-- Allowed operation: ALL
-- Target roles: authenticated
-- Policy definition:

bucket_id = 'avatars'

-- ========================================
-- BUCKET SETTINGS
-- ========================================
-- Make sure your avatars bucket has these settings:
-- ✅ Public bucket: YES (enabled)
-- ✅ File size limit: 2097152 (2MB)
-- ✅ Allowed MIME types: image/jpeg, image/png, image/gif, image/webp
--
-- ========================================
