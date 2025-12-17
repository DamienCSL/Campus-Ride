# Driver License Verification Setup Guide

## Overview
This feature allows drivers to upload their license photo during registration, admins to review it before approval, and rejected drivers to resubmit with a new license.

## Database Setup

### 1. Add license_photo_url Column
Run the SQL file: [`add_license_photo_column.sql`](add_license_photo_column.sql)

This will:
- Add `license_photo_url` text column to `drivers` table
- Document the schema change

### 2. Create Storage Bucket
In Supabase Dashboard → Storage:

1. **Create Bucket:**
   - Click "New bucket"
   - Name: `driver_licenses`
   - Make it **public** (so admins can view images)

2. **Add Storage Policies:**
   Run the storage policies from `add_license_photo_column.sql` or add them manually in the Supabase Dashboard:
   
   - **Users can upload their own license** (INSERT)
   - **Users can update their own license** (UPDATE)
   - **Admins can view all licenses** (SELECT for admin role)
   - **Drivers can view their own license** (SELECT for own folder)

## Features Implemented

### 1. Driver Registration with License Upload
**File:** [`lib/driver_register.dart`](lib/driver_register.dart)

- Added image picker for license photo
- Visual preview of selected image
- Validation: license photo is required
- Upload to `driver_licenses/{userId}/{timestamp}.jpg`
- Store URL in `drivers.license_photo_url`

**User Experience:**
- Large upload box with clear instructions
- "Tap to upload license photo" prompt
- Image preview after selection
- Green checkmark confirmation
- Remove button to change photo

### 2. Admin Approval with License Review
**File:** [`lib/admin_driver_approval.dart`](lib/admin_driver_approval.dart)

- Display license photo in driver detail modal
- 300px height preview image
- Tap image to view fullscreen
- InteractiveViewer for zoom/pan (pinch to zoom, drag to pan)
- Fallback for missing/failed images
- License photo visible before approve/reject decision

**Admin Experience:**
- Click pending driver → see all details
- License photo prominently displayed
- "Tap image to view fullscreen" hint
- Fullscreen viewer with zoom up to 5x
- Close button in top-right corner

### 3. Rejection with Resubmission Flow
**File:** [`lib/driver_license_resubmit.dart`](lib/driver_license_resubmit.dart)

When a driver is rejected:
- Rejection reason displayed in red card
- Current license photo shown (if exists)
- Upload new license photo
- Resubmit button resets approval status
- Sets `is_approved=false`, `is_rejected=false`
- Clears rejection reason and timestamp

**Driver Experience:**
- Try to go online → rejection dialog pops up
- Shows rejection reason in colored box
- "Resubmit License" button navigates to resubmission page
- Upload new photo with clear instructions
- Submit → application returns to pending status
- Admin receives fresh submission to review

### 4. Driver Dashboard Integration
**File:** [`lib/driver_dashboard.dart`](lib/driver_dashboard.dart)

Modified `toggleAvailability`:
- Check approval status before going online
- If rejected: show special dialog with rejection reason
- "Resubmit License" button in dialog
- Navigates to resubmission page
- Prevents going online until approved

## User Flow

### New Driver Registration
1. Fill out registration form (name, email, password, etc.)
2. **NEW:** Upload driver license photo (required)
3. Submit registration
4. Account created, driver record with `is_approved=false`
5. Status: **Pending Admin Approval**

### Admin Reviews Application
1. Open Admin Dashboard → Driver Approvals
2. See pending driver in list
3. Click driver to see details
4. **NEW:** Review license photo
   - View in modal at 300px height
   - Click to open fullscreen viewer
   - Zoom/pan to inspect details
5. Decision:
   - **Approve:** Driver can go online
   - **Reject:** Enter reason (e.g., "License expired", "Photo unclear")

### Rejected Driver Resubmits
1. Driver tries to go online
2. Rejection dialog appears with reason
3. Click "Resubmit License"
4. See current rejection reason
5. See old license photo (for reference)
6. **Upload new license photo**
7. Click "Submit for Re-approval"
8. Status changes from rejected → pending
9. Admin sees fresh application with new photo

### Approved Driver Goes Online
1. Driver approved by admin
2. Toggle switch to go online
3. ✅ Success! Now can receive ride requests

## File Structure

```
lib/
├── driver_register.dart          # Registration with license upload
├── admin_driver_approval.dart    # Admin approval with photo review
├── driver_license_resubmit.dart  # Resubmission page for rejected drivers
├── driver_dashboard.dart         # Dashboard with rejection handling
└── main.dart                     # Added route for resubmission page

SQL files:
├── add_license_photo_column.sql  # Database setup script
```

## Testing Checklist

### Driver Registration
- [ ] Register new driver
- [ ] Try to submit without license photo → error
- [ ] Upload license photo → green checkmark appears
- [ ] Remove photo → can upload different one
- [ ] Submit → profile, driver, vehicle created
- [ ] Check database: `license_photo_url` populated

### Admin Approval
- [ ] Open admin driver approval page
- [ ] See pending driver in list
- [ ] Click driver → modal opens
- [ ] License photo displays correctly
- [ ] Click photo → fullscreen viewer opens
- [ ] Pinch to zoom, drag to pan
- [ ] Close fullscreen viewer
- [ ] Approve driver → notification sent
- [ ] Verify driver removed from pending list

### Rejection & Resubmission
- [ ] Admin rejects driver with reason "License expired"
- [ ] Login as rejected driver
- [ ] Try to go online → rejection dialog appears
- [ ] Dialog shows rejection reason
- [ ] Click "Resubmit License"
- [ ] Resubmission page shows rejection reason
- [ ] Resubmission page shows old license photo
- [ ] Upload new license photo
- [ ] Submit → success message
- [ ] Check database: `is_rejected=false`, `is_approved=false`
- [ ] Admin sees driver back in pending list
- [ ] Admin sees new license photo
- [ ] Admin approves → driver can go online

### Edge Cases
- [ ] No license photo uploaded → placeholder message
- [ ] Image fails to load → broken image icon
- [ ] Large image → loads smoothly, zoomable
- [ ] Driver with no rejection reason → generic message
- [ ] Multiple resubmissions → latest photo shown

## Storage Structure

```
driver_licenses/
└── {user_id}/
    ├── 1702765432000.jpg  # Original submission
    └── 1702876543000.jpg  # Resubmission (newer timestamp)
```

Each driver's licenses are in their own folder (`{user_id}/`), allowing:
- RLS policy: driver can only access their folder
- Multiple resubmissions: new timestamp for each upload
- Admin access: can view all folders

## Security Considerations

1. **RLS Policies:**
   - Drivers can only upload to their own folder
   - Admins can view all folders
   - Public bucket allows direct image URLs (needed for display)

2. **Validation:**
   - License photo required during registration
   - Image quality: maxWidth 1920, quality 85%
   - Content type enforced: image/jpeg

3. **Resubmission:**
   - Resets approval status to prevent bypass
   - Clears rejection data so admin sees clean slate
   - Preserves original upload history (different timestamps)

## Troubleshooting

### Image Not Displaying
- Check storage bucket is public
- Verify URL format: `https://{project}.supabase.co/storage/v1/object/public/driver_licenses/{userId}/{timestamp}.jpg`
- Check RLS policies allow SELECT for admins

### Upload Fails
- Verify storage bucket `driver_licenses` exists
- Check RLS INSERT policy allows authenticated user to upload
- Verify user is authenticated
- Check folder name matches user ID

### Resubmit Button Not Working
- Verify route added to `main.dart`
- Check import: `import 'driver_license_resubmit.dart';`
- Ensure route path matches: `'/driver_license_resubmit'`

## Future Enhancements

Consider adding:
- [ ] Auto-expire rejections after 30 days
- [ ] OCR to extract license number automatically
- [ ] License expiry date field with validation
- [ ] Photo quality check (resolution, file size)
- [ ] Support for multiple document types (license, insurance, vehicle registration)
- [ ] Admin comment/note system beyond rejection reason
- [ ] Email notification when resubmission is reviewed
- [ ] Statistics: approval rate, average review time

## Code Snippets

### Query Driver with License Photo
```dart
final driver = await supabase
    .from('drivers')
    .select('*, license_photo_url')
    .eq('id', userId)
    .maybeSingle();

final licenseUrl = driver['license_photo_url'];
```

### Upload License Photo
```dart
final path = 'driver_licenses/$userId/${DateTime.now().millisecondsSinceEpoch}.jpg';
await supabase.storage
    .from('driver_licenses')
    .upload(path, file, fileOptions: FileOptions(upsert: true));

final url = supabase.storage.from('driver_licenses').getPublicUrl(path);
```

### Reset Approval Status on Resubmission
```dart
await supabase.from('drivers').update({
  'license_photo_url': newUrl,
  'is_approved': false,
  'is_rejected': false,
  'rejection_reason': null,
  'rejected_at': null,
}).eq('id', userId);
```
