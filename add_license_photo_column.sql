-- Add license_photo_url column to drivers table for driver license verification
-- This allows admins to review driver licenses before approval

-- Add the column if it doesn't exist
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'drivers' AND column_name = 'license_photo_url'
  ) THEN
    ALTER TABLE public.drivers 
    ADD COLUMN license_photo_url text;
  END IF;
END $$;

-- Create storage bucket for driver licenses if it doesn't exist
-- Run this in the Supabase Dashboard -> Storage section:
-- 1. Create a new bucket named "driver_licenses"
-- 2. Set it to public (so admins can view the images)
-- 3. Add these policies:

-- Policy 1: Allow authenticated users to upload their own license
CREATE POLICY "Users can upload their own license"
ON storage.objects FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'driver_licenses' AND
  (storage.foldername(name))[1] = auth.uid()::text
);

-- Policy 2: Allow users to update their own license
CREATE POLICY "Users can update their own license"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'driver_licenses' AND
  (storage.foldername(name))[1] = auth.uid()::text
);

-- Policy 3: Allow admins to view all licenses
CREATE POLICY "Admins can view all licenses"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'driver_licenses' AND
  EXISTS (
    SELECT 1 FROM profiles
    WHERE profiles.id = auth.uid()
    AND profiles.role = 'admin'
  )
);

-- Policy 4: Allow drivers to view their own license
CREATE POLICY "Drivers can view their own license"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'driver_licenses' AND
  (storage.foldername(name))[1] = auth.uid()::text
);

-- Verify the column was added
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'drivers' AND column_name = 'license_photo_url';
