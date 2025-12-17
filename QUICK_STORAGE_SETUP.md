# 🚀 Quick Setup - Driver License Storage (5 minutes)

## The Error You're Getting
```
StorageException: new row violates row-level security policy (403)
```

**Why:** Storage bucket `driver_licenses` doesn't exist or has no permissions.

## Fix It Now ⚡

### 1️⃣ Go to Supabase Dashboard
- Project → **Storage** (left menu)

### 2️⃣ Create Bucket
- **Create a new bucket**
- Name: `driver_licenses`
- Toggle: **Make it Public** ✅
- Click **Create bucket**

### 3️⃣ Add Policies (4 quick policies)

Click **driver_licenses** bucket → **Policies** (top right)

**For each policy below:** Click **New policy** → **For full customization** → Fill in → **Save**

---

**Policy #1: Upload (users can upload their own)**
```
Name: Users can upload their own license
Allow: INSERT
Role: authenticated
CHECK: ((bucket_id = 'driver_licenses'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text))
```

**Policy #2: Update (users can update their own)**
```
Name: Users can update their own license
Allow: UPDATE
Role: authenticated
USING: ((bucket_id = 'driver_licenses'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text))
CHECK: ((bucket_id = 'driver_licenses'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text))
```

**Policy #3: View (admins can see all)**
```
Name: Admins can view all licenses
Allow: SELECT
Role: authenticated
USING: ((bucket_id = 'driver_licenses'::text) AND EXISTS ( SELECT 1 FROM profiles WHERE ((profiles.id = auth.uid()) AND ((profiles.role)::text = 'admin'::text))))
```

**Policy #4: View Own (drivers can see their own)**
```
Name: Drivers can view their own license
Allow: SELECT
Role: authenticated
USING: ((bucket_id = 'driver_licenses'::text) AND ((storage.foldername(name))[1] = (auth.uid())::text))
```

---

## ✅ Verify It Works

After setup, test registration:
1. **Register new driver** in app
2. **Upload license photo** ← should work now
3. **Submit** → driver record created
4. Check Supabase Storage → see `driver_licenses/{userId}/` folder with your photo

## That's It! 🎉

Now admins can review licenses and drivers can resubmit if rejected.

---

## Still Not Working?

Run this SQL in **Supabase SQL Editor** to verify:

```sql
-- Check bucket exists
SELECT id, name, public FROM storage.buckets WHERE id = 'driver_licenses';

-- Check policies (should show 4 rows)
SELECT policyname, action FROM pg_policies 
WHERE tablename = 'objects' 
AND policyname LIKE '%license%';
```

Expected output:
- 1 bucket row with `public = true`
- 4 policy rows (INSERT, UPDATE, SELECT, SELECT)

If missing, either:
1. Dashboard setup didn't save (try again)
2. Or run SQL to create them

Contact support if policies still don't work after SQL.
