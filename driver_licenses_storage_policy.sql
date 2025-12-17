-- ========================================
-- DRIVER_LICENSES STORAGE BUCKET - RLS POLICIES
-- ========================================
-- 
-- Follow these steps in Supabase Dashboard:
--
-- STEP 1: Go to Storage in your Supabase Dashboard
-- STEP 2: Select the "driver_licenses" bucket
-- STEP 3: Go to the "Policies" tab
-- STEP 4: DELETE all existing policies for this bucket
-- STEP 5: Click "New Policy" for each policy below
--
-- ========================================

-- POLICY 1: Allow authenticated users to INSERT (upload their own)
-- ========================================
-- Policy Name: Authenticated users can upload their license
-- Allowed operation: INSERT
-- Target roles: authenticated
-- WITH CHECK expression:

(bucket_id = 'driver_licenses' AND (storage.foldername(name))[1] = auth.uid()::text)

-- ========================================

-- POLICY 2: Allow authenticated users to UPDATE their own
-- ========================================
-- Policy Name: Users can update their own license
-- Allowed operation: UPDATE
-- Target roles: authenticated
-- USING expression:

(bucket_id = 'driver_licenses' AND (storage.foldername(name))[1] = auth.uid()::text)

-- WITH CHECK expression:

(bucket_id = 'driver_licenses' AND (storage.foldername(name))[1] = auth.uid()::text)

-- ========================================

-- POLICY 3: Allow authenticated users to SELECT their own
-- ========================================
-- Policy Name: Users can view their own license
-- Allowed operation: SELECT
-- Target roles: authenticated
-- USING expression:

(bucket_id = 'driver_licenses' AND (storage.foldername(name))[1] = auth.uid()::text)

-- ========================================

-- POLICY 4: Allow authenticated users to DELETE their own
-- ========================================
-- Policy Name: Users can delete their own license
-- Allowed operation: DELETE
-- Target roles: authenticated
-- USING expression:

(bucket_id = 'driver_licenses' AND (storage.foldername(name))[1] = auth.uid()::text)

-- ========================================

-- POLICY 5: Allow admins to SELECT all licenses
-- ========================================
-- Policy Name: Admins can view all licenses
-- Allowed operation: SELECT
-- Target roles: authenticated
-- USING expression:

(bucket_id = 'driver_licenses' AND EXISTS (
  SELECT 1 FROM public.profiles 
  WHERE profiles.id = auth.uid() AND profiles.role = 'admin'
))

-- ========================================
-- NOTES:
-- ========================================
-- 
-- • The upload path MUST be: driver_licenses/{user.id}/filename.jpg
-- • (storage.foldername(name))[1] extracts the first folder (user.id)
-- • This ensures users can only access their own license files
-- • Admins can view all licenses for approval purposes
-- • Make sure the bucket is PUBLIC (Configuration tab)
--
-- ========================================
