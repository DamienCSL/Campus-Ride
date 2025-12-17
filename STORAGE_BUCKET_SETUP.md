# Storage Setup for Driver License Verification - Quick Guide

## Problem
Getting "403 Unauthorized" or "new row violates row-level security policy" when uploading license photos.

**Cause:** The `driver_licenses` storage bucket doesn't exist or RLS policies aren't configured.

## Solution - Dashboard Setup (Easiest)

### Step 1: Create Storage Bucket

1. Go to **Supabase Dashboard** → Select your project
2. Click **Storage** (left sidebar)
3. Click **Create a new bucket**
4. **Bucket name:** `driver_licenses` (must be exact)
5. **Make it Public:** Toggle ON (so the images are viewable)
6. Click **Create bucket**

Expected result: You see `driver_licenses` in the storage list

### Step 2: Add RLS Policies

After creating the bucket, click **driver_licenses** to open it.

#### Policy 1: Allow Users to Upload Their Own License

1. Click **Policies** (top-right dropdown next to bucket name)
2. Click **New policy** → **For full customization**
3. Configure:
   - **Policy name:** `Users can upload their own license`
   - **Allow:** `INSERT`
   - **For role:** `authenticated`
   - **USING expression:** Leave blank
   - **WITH CHECK expression:** Paste this:
     ```
     ((bucket_id = 'driver_licenses'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text))
     ```
4. Click **Review**
5. Click **Save policy**

#### Policy 2: Allow Users to Update Their Own License

1. Click **New policy** → **For full customization**
2. Configure:
   - **Policy name:** `Users can update their own license`
   - **Allow:** `UPDATE`
   - **For role:** `authenticated`
   - **USING expression:** Paste this:
     ```
     ((bucket_id = 'driver_licenses'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text))
     ```
   - **WITH CHECK expression:** Same as USING
3. Click **Save policy**

#### Policy 3: Allow Admins to View All Licenses

1. Click **New policy** → **For full customization**
2. Configure:
   - **Policy name:** `Admins can view all licenses`
   - **Allow:** `SELECT`
   - **For role:** `authenticated`
   - **USING expression:** Paste this:
     ```
     ((bucket_id = 'driver_licenses'::text) AND EXISTS ( SELECT 1 FROM profiles WHERE ((profiles.id = auth.uid()) AND ((profiles.role)::text = 'admin'::text))))
     ```
3. Click **Save policy**

#### Policy 4: Allow Drivers to View Their Own License

1. Click **New policy** → **For full customization**
2. Configure:
   - **Policy name:** `Drivers can view their own license`
   - **Allow:** `SELECT`
   - **For role:** `authenticated`
   - **USING expression:** Paste this:
     ```
     ((bucket_id = 'driver_licenses'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text))
     ```
3. Click **Save policy**

### Verification

After adding all policies, you should see:
- ✅ Bucket `driver_licenses` exists and is **public**
- ✅ 4 policies listed:
  1. INSERT (users can upload)
  2. UPDATE (users can update)
  3. SELECT (admins can view all)
  4. SELECT (drivers can view own)

## Alternative: SQL Setup (Advanced)

If you prefer SQL, run this in **Supabase SQL Editor**:

```sql
-- Create driver_licenses bucket (run in SQL editor)
INSERT INTO storage.buckets (id, name, public)
VALUES ('driver_licenses', 'driver_licenses', true)
ON CONFLICT (id) DO NOTHING;

-- Policy 1: Allow authenticated users to upload (for registration flow)
-- Note: No folder check here because user may not be logged in during registration
CREATE POLICY "Allow authenticated uploads"
ON storage.objects FOR INSERT
TO authenticated, service_role
WITH CHECK (bucket_id = 'driver_licenses');

-- Policy 2: Users can update their own license (after login)
CREATE POLICY "Users can update their own license"
ON storage.objects FOR UPDATE
TO authenticated
USING (
  bucket_id = 'driver_licenses' AND
  (storage.foldername(name))[1] = auth.uid()::text
)
WITH CHECK (
  bucket_id = 'driver_licenses' AND
  (storage.foldername(name))[1] = auth.uid()::text
);

-- Policy 3: Admins can view all licenses
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

-- Policy 4: Drivers can view their own license
CREATE POLICY "Drivers can view their own license"
ON storage.objects FOR SELECT
TO authenticated
USING (
  bucket_id = 'driver_licenses' AND
  (storage.foldername(name))[1] = auth.uid()::text
);

-- Verify bucket exists
SELECT id, name, public FROM storage.buckets WHERE id = 'driver_licenses';
```

## Troubleshooting

### Registration Upload Failing (403 Error)

**Problem:** User uploads license photo DURING registration (before login), so `auth.uid()` is NULL.

**Solution:** Modify the INSERT policy to allow authenticated uploads without folder check:

```sql
-- Drop the old restrictive policy
DROP POLICY IF EXISTS "Users can upload their own license" ON storage.objects;

-- Create new permissive INSERT policy
CREATE POLICY "Allow authenticated uploads"
ON storage.objects FOR INSERT
TO authenticated, service_role
WITH CHECK (bucket_id = 'driver_licenses');
```

This allows:
- Registration flow: User uploads before logging in ✅
- Folder check: Still applied on UPDATE/SELECT ✅
- Security: Still protected by RLS on views ✅

### Still Getting 403 Error?

**Check 1: Bucket exists**
```sql
SELECT id, name, public FROM storage.buckets WHERE id = 'driver_licenses';
```
Expected: 1 row, `public = true`

**Check 2: Policies exist**
```sql
SELECT policyname, action, definition FROM pg_policies 
WHERE schemaname = 'storage' AND tablename = 'objects' 
AND policyname LIKE '%license%';
```
Expected: 4 rows (INSERT, UPDATE, SELECT x2)

**Check 3: User is authenticated**
- Make sure you're logged in as a driver when uploading
- Check auth token is valid

**Check 4: Path format**
- Uploads should go to: `driver_licenses/{userId}/{timestamp}.jpg`
- The `{userId}` is the authenticated user's ID
- This matches the `(storage.foldername(name))[1]` policy check

### Wrong Folder Structure?

If you're uploading to wrong path, code will fail the policy check. Verify in code:

```dart
// This path must match the policy: driver_licenses/{userId}/*
final licensePhotoPath = 'driver_licenses/$userId/${DateTime.now().millisecondsSinceEpoch}.jpg';
```

## Next Steps

After setting up storage:

1. **Test driver registration:**
   - Register a new driver
   - Upload license photo
   - Should succeed with no 403 error

2. **Check storage:**
   - Go to Supabase Storage
   - Navigate to `driver_licenses/` folder
   - See your uploaded files

3. **Test admin view:**
   - Login as admin
   - Open driver approval page
   - License photo should display

## Important Notes

- **Public bucket:** Images are accessible via direct URL (needed for display)
- **RLS policies:** Still control who can upload/download (users their own, admins all)
- **Folder structure:** `driver_licenses/{userId}/` - each user's files in their folder
- **File naming:** Uses timestamp to avoid collisions on resubmission

## Reference: Expected URL Format

After successful upload, image URL will be:
```
https://{project-id}.supabase.co/storage/v1/object/public/driver_licenses/{userId}/{timestamp}.jpg
```

Example:
```
https://abc123.supabase.co/storage/v1/object/public/driver_licenses/d7186ae0-e076-43fc-9522-33275e4e60f2/1702876543000.jpg
```

## Questions?

If you still get 403:
1. Share your user ID and the exact file path you're uploading to
2. Run the verification SQL above and share results
3. Check browser console for detailed error message
