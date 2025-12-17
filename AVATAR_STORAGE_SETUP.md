# Avatar Storage Setup Guide

This guide will help you set up the avatars storage bucket with proper RLS policies in Supabase.

## Step 1: Create the Avatars Bucket (if not exists)

1. Go to your Supabase Dashboard
2. Navigate to **Storage** in the left sidebar
3. If you don't have an `avatars` bucket, click **"New Bucket"**
4. Configure the bucket:
   - **Name:** `avatars`
   - **Public bucket:** ✅ **Enable** (allows public read access to view avatars)
   - **File size limit:** `2 MB` (suitable for profile pictures)
   - **Allowed MIME types:** 
     - `image/jpeg`
     - `image/png`
     - `image/gif`
     - `image/webp`

## Step 2: Apply RLS Policies via Dashboard UI

⚠️ **Important:** Storage policies must be created through the Supabase Dashboard UI, not SQL Editor.

### Method 1: Full Security (Recommended)

1. Go to **Storage** in your Supabase Dashboard
2. Click on the **avatars** bucket
3. Click the **Policies** tab
4. Click **"New Policy"** and create each policy below:

#### Policy 1: Upload Policy
- **Policy Name:** `Users can upload their own avatar`
- **Policy Behavior:** Permissive
- **Allowed operation:** `INSERT`
- **Target roles:** `authenticated`
- **WITH CHECK expression:**
  ```sql
  (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text)
  ```

#### Policy 2: Update Policy
- **Policy Name:** `Users can update their own avatar`
- **Policy Behavior:** Permissive
- **Allowed operation:** `UPDATE`
- **Target roles:** `authenticated`
- **USING expression:**
  ```sql
  (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text)
  ```
- **WITH CHECK expression:**
  ```sql
  (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text)
  ```

#### Policy 3: Delete Policy
- **Policy Name:** `Users can delete their own avatar`
- **Policy Behavior:** Permissive
- **Allowed operation:** `DELETE`
- **Target roles:** `authenticated`
- **USING expression:**
  ```sql
  (bucket_id = 'avatars' AND (storage.foldername(name))[1] = auth.uid()::text)
  ```

#### Policy 4: View Policy
- **Policy Name:** `Anyone can view avatars`
- **Policy Behavior:** Permissive
- **Allowed operation:** `SELECT`
- **Target roles:** `public`
- **USING expression:**
  ```sql
  bucket_id = 'avatars'
  ```

### Method 2: Simple Policy (Quick Setup for Testing)

If you just want to test quickly without strict user isolation:

1. Go to **Storage** → **avatars** → **Policies**
2. Click **"New Policy"**
3. Create ONE policy with these settings:
   - **Policy Name:** `Authenticated users full access`
   - **Policy Behavior:** Permissive
   - **Allowed operation:** `ALL`
   - **Target roles:** `authenticated`
   - **Policy definition:**
     ```sql
     bucket_id = 'avatars'
     ```

This gives all authenticated users full access to the avatars bucket (less secure but easier for testing).

### Screenshots Guide

**Creating a policy:**
1. Storage → avatars → Policies tab → New Policy
2. Fill in policy name
3. Select operation type (INSERT, UPDATE, DELETE, SELECT, or ALL)
4. Select target roles (authenticated or public)
5. Enter the policy expression
6. Click "Save"

## Step 3: Verify the Setup

### Check Bucket Settings
```sql
-- View bucket configuration
SELECT * FROM storage.buckets WHERE name = 'avatars';
```

### Check RLS Policies
```sql
-- View all avatar-related policies
SELECT * FROM pg_policies 
WHERE tablename = 'objects' 
AND policyname LIKE '%avatar%';
```

You should see 4 policies:
1. `Users can upload their own avatar` (INSERT)
2. `Users can update their own avatar` (UPDATE)
3. `Users can delete their own avatar` (DELETE)
4. `Anyone can view avatars` (SELECT)

## Step 4: Test Upload Functionality

### From the App
1. **User Profile:**
   - Open the app
   - Go to Profile → Edit Profile
   - Tap on the avatar/camera icon
   - Select an image from gallery
   - Save changes

2. **Driver Profile:**
   - Log in as a driver
   - Go to Profile → Edit Profile
   - Tap on the avatar/camera icon
   - Select an image from gallery
   - Save changes

### Expected Behavior
- ✅ Image uploads successfully
- ✅ Avatar displays in the app
- ✅ Avatar URL is saved to `profiles.avatar_url`
- ✅ File is stored at: `avatars/{user_id}/avatar.jpg`

### Check Debug Output
Look for these messages in your Flutter debug console:
```
📤 Uploading avatar to: {user_id}/avatar.jpg
✅ Avatar uploaded successfully: https://...
```

## Troubleshooting

### Error: "new row violates row-level security policy"
**Cause:** RLS policies not properly configured or user not authenticated

**Solution:**
1. Re-run `avatars_storage_policy.sql`
2. Verify user is authenticated: `supabase.auth.currentUser != null`
3. Check bucket exists and is named exactly `avatars`

### Error: "The resource already exists"
**Cause:** Trying to upload without `upsert: true`

**Solution:** Code already includes `upsert: true` in FileOptions

### Avatar Not Displaying
**Cause:** Public access not enabled or incorrect URL

**Solution:**
1. Check bucket is public in Supabase Dashboard
2. Verify avatar_url is saved correctly in profiles table
3. Check network connectivity
4. Add cache-busting timestamp (already implemented)

### Upload Fails with No Error
**Cause:** File too large or wrong MIME type

**Solution:**
1. Check file size < 2MB
2. Ensure image is JPEG, PNG, GIF, or WebP
3. Check allowed MIME types in bucket settings

## File Structure

After users upload avatars, your storage will look like:
```
avatars/
├── {user_id_1}/
│   └── avatar.jpg
├── {user_id_2}/
│   └── avatar.jpg
└── {user_id_3}/
    └── avatar.jpg
```

This structure:
- ✅ Keeps files organized by user
- ✅ Matches RLS policy requirements
- ✅ Prevents conflicts between users
- ✅ Makes it easy to manage/delete user data

## Code Implementation

### User Edit Profile (`edit_profile.dart`)
```dart
// Upload with user-specific folder
final filePath = "$userId/avatar.jpg";
await supabase.storage.from("avatars").upload(
  filePath, 
  imageFile!, 
  fileOptions: FileOptions(
    upsert: true,
    contentType: 'image/jpeg',
    cacheControl: '3600',
  )
);
```

### Driver Edit Profile (`driver_edit_profile.dart`)
```dart
// Same implementation - drivers and users share the avatars bucket
final filePath = "$userId/avatar.jpg";
await supabase.storage.from("avatars").upload(
  filePath, 
  imageFile!, 
  fileOptions: FileOptions(
    upsert: true,
    contentType: 'image/jpeg',
    cacheControl: '3600',
  )
);
```

## Security Notes

1. **User Isolation:** Users can only modify their own folder (`{user_id}/`)
2. **Public Read:** Anyone can view avatars (necessary for displaying in app)
3. **Authenticated Write:** Only logged-in users can upload
4. **File Overwrite:** `upsert: true` allows updating existing avatar
5. **Cache Control:** 1-hour cache with timestamp bust on update

## Additional Features

### Image Optimization
The code includes automatic image transformation:
```dart
transform: TransformOptions(
  width: 400,
  height: 400,
)
```
This reduces bandwidth and improves load times.

### Cache Busting
URLs include timestamp to force refresh after upload:
```dart
final publicUrl = supabase.storage
    .from("avatars")
    .getPublicUrl(filePath) + '?t=$timestamp';
```

---

## Summary Checklist

- ✅ Created `avatars` bucket with public access enabled
- ✅ Set file size limit to 2MB
- ✅ Configured allowed MIME types for images
- ✅ Ran `avatars_storage_policy.sql` to set up RLS policies
- ✅ Verified 4 policies exist for avatars
- ✅ Tested upload from user profile
- ✅ Tested upload from driver profile
- ✅ Confirmed avatars display correctly in app

If all items are checked, your avatar storage system is fully configured! 🎉
