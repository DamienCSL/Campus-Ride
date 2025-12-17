# Driver Approval System Troubleshooting Guide

## Issue: Drivers not appearing in admin pending approval list

### Root Cause
The admin approval page queries for drivers where `is_approved = false` AND `is_rejected = false`. If these fields are NULL or not set during registration, the driver won't appear in the pending list.

### Step-by-Step Fix

#### 1. Check Current Database State
Run the diagnostic SQL file to see what's in your database:

**File: `check_drivers_status.sql`**

This will show:
- Total number of drivers
- Count by approval status
- All driver records with full details
- Drivers needing migration (NULL fields)
- Profiles with 'driver' role but no driver record

#### 2. Fix Existing Driver Records
If you have drivers registered before the fix, run the migration SQL:

**File: `fix_driver_approval_fields.sql`**

This will:
- Set `is_approved = false` for any NULL values
- Set `is_rejected = false` for any NULL values  
- Set `is_verified = false` for any NULL values

After running this, existing drivers will appear in the pending approval list.

#### 3. Test New Driver Registration
The code has been updated to explicitly set these fields:

**File: `lib/driver_register.dart`** (lines 106-114)
```dart
await supabase.from('drivers').insert({
  'id': userId,
  'license_number': license,
  'vehicle_id': vehicleId,
  'is_verified': false,
  'is_approved': false,  // ✅ Now explicitly set
  'is_rejected': false,  // ✅ Now explicitly set
}).select();
```

New registrations will now automatically set these fields correctly.

#### 4. Verify with Debug Logs

**In Driver Registration:**
Look for these logs when a driver registers:
```
🔄 [driver_register] Calling RPC to create profile...
✅ [driver_register] Profile created via RPC
🔄 [driver_register] Inserting into vehicles table...
✅ [driver_register] Vehicle record inserted
🔄 [driver_register] Inserting into drivers table...
✅ [driver_register] Driver record inserted
   Driver data: [...]
🔍 [driver_register] Verification query result: {...}
```

If you see an error or the verification shows `null`, there's a database constraint issue.

**In Admin Approval Page:**
When the admin opens the driver approval page:
```
🔄 [admin_driver_approval] Loading pending drivers...
   Query: SELECT * FROM drivers WHERE is_approved = false AND is_rejected = false
✅ [admin_driver_approval] Found X pending drivers
   Data: [...]
📊 [admin_driver_approval] Total drivers in database: Y
   - Driver xxx: is_approved=false, is_rejected=false
```

This shows:
- How many pending drivers were found
- What data was returned
- Total driver count for comparison
- Approval status of each driver

### Common Issues

#### Issue 1: Profile created but driver record not created
**Symptoms:** Profile exists in database, but no entry in `drivers` table

**Possible Causes:**
- Foreign key constraint on `vehicle_id` 
- Missing required fields
- RLS policy blocking insert

**Solution:**
Check the debug logs for the actual error. The code now includes a verification query that will throw an exception if the driver record wasn't created.

#### Issue 2: Driver record created but fields are NULL
**Symptoms:** Driver appears in database but not in admin pending list

**Solution:**
Run `fix_driver_approval_fields.sql` to set NULL fields to `false`

#### Issue 3: RLS (Row Level Security) blocking queries
**Symptoms:** Admin sees 0 pending drivers, but database has records

**Solution:**
Check if RLS policies on `drivers` table allow admin users to read all records:
```sql
-- Check existing policies
SELECT * FROM pg_policies WHERE tablename = 'drivers';

-- Ensure admin can read all drivers
CREATE POLICY "Admins can read all drivers"
ON drivers FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM profiles
    WHERE profiles.id = auth.uid()
    AND profiles.role = 'admin'
  )
);
```

### Testing Checklist

- [ ] Run `check_drivers_status.sql` in Supabase SQL editor
- [ ] Run `fix_driver_approval_fields.sql` if any drivers have NULL fields
- [ ] Register a new test driver
- [ ] Check debug console for registration logs
- [ ] Verify driver record created with correct fields
- [ ] Open admin driver approval page
- [ ] Check debug console for query logs
- [ ] Verify test driver appears in pending list
- [ ] Test approve/reject functionality
- [ ] Verify approved driver no longer appears in pending list

### Database Schema Reference

```sql
CREATE TABLE drivers (
  id uuid PRIMARY KEY,
  license_number text,
  vehicle_id uuid,
  is_verified boolean DEFAULT false,
  is_approved boolean DEFAULT false,  -- Required for pending query
  is_rejected boolean DEFAULT false,  -- Required for pending query
  rejection_reason text,
  approved_at timestamp with time zone,
  rejected_at timestamp with time zone,
  -- other fields...
)
```

### Quick Fixes

**If driver still not appearing after all fixes:**

1. **Check browser console** - Look for Supabase errors
2. **Check Supabase dashboard** - Manually verify the driver record exists
3. **Check RLS policies** - Ensure admin can read drivers table
4. **Force refresh** - Click the refresh button in admin approval page
5. **Restart app** - Close and restart the Flutter app
6. **Clear app data** - Sometimes cached authentication causes issues

### Support

If issues persist after following this guide:
1. Share the output from `check_drivers_status.sql`
2. Share the debug console logs from driver registration
3. Share the debug console logs from admin approval page load
4. Check Supabase logs for any database errors
