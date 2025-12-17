# Driver Onboarding Setup Guide

## Overview
New drivers must complete an onboarding flow after registration to upload their driver license. This ensures email verification is complete before accessing storage, avoiding RLS policy issues.

## Architecture

### New Onboarding Flow
```
Register Driver → Email Confirmation → Login → Auto-redirect to Onboarding → Upload License → Admin Approval → Dashboard (Can go online)
```

### Files Changed/Created

#### 1. **driver_onboarding.dart** (NEW)
- **Purpose**: Post-login tutorial and license upload checklist
- **Features**:
  - Welcome screen explaining onboarding
  - Checklist with 3 items:
    1. "Upload Driver License" (required action)
    2. "Review Profile" (auto-completed at registration)
    3. "Wait for Admin Approval" (shows when license uploaded)
  - License photo picker from gallery
  - Upload to `driver_licenses` bucket
  - Success confirmation and "Go to Dashboard" button
  - Prevents back button until all steps completed
- **Flow**:
  1. User picks license photo
  2. System uploads to `driver_licenses/{userId}/{timestamp}.jpg`
  3. Updates `drivers.license_photo_url` with public URL
  4. Marks checklist item as completed
  5. Shows completion message
  6. User can proceed to dashboard

#### 2. **main.dart** (UPDATED)
- **Changes**:
  - Added import: `import 'driver_onboarding.dart';`
  - Added route: `'/driver_onboarding': (context) => const DriverOnboarding(),`
  - Updated `_handleSplashNavigation()` to detect first-time drivers:
    ```dart
    // Check if driver has completed onboarding (license uploaded)
    if (role == 'driver') {
      final driver = await supabase
          .from('drivers')
          .select('license_photo_url')
          .eq('id', userId)
          .maybeSingle();
      
      if (driver == null || driver['license_photo_url'] == null) {
        // New driver - show onboarding
        navigatorKey.currentState?.pushReplacement(
          MaterialPageRoute(builder: (_) => const DriverOnboarding()),
        );
      } else {
        // License uploaded - go to dashboard
        navigatorKey.currentState?.pushReplacement(
          MaterialPageRoute(builder: (_) => const DriverDashboard()),
        );
      }
    }
    ```

#### 3. **driver_dashboard.dart** (UPDATED)
- **Changes**:
  - Updated `toggleAvailability()` method to check `license_photo_url`:
    ```dart
    // Check if license is uploaded
    final licensePhotoUrl = driverData['license_photo_url'] as String?;
    if (licensePhotoUrl == null || licensePhotoUrl.isEmpty) {
      _showApprovalDialog(
        'License Not Uploaded',
        'Please upload your driver license in onboarding before going online.',
        Icons.credit_card,
        Colors.orange,
      );
      return;
    }
    ```
  - Prevents drivers from going online if `license_photo_url` is NULL
  - Shows "License Not Uploaded" dialog with guidance

#### 4. **driver_register.dart** (SIMPLIFIED)
- **Changes**:
  - Removed license photo upload from registration
  - Removed `dart:io` import
  - Removed `package:image_picker` import
  - Removed `_licensePhotoFile` variable
  - Removed `_buildLicensePhotoUpload()` method
  - Removed `_pickLicensePhoto()` method
  - Driver created with `license_photo_url: NULL`
- **Result**: Registration now only collects basic info (name, email, password, license number, vehicle)

### Database Schema (No Changes Required)
The `drivers` table already has:
- `license_photo_url` (TEXT, NULL by default)
- `is_approved` (BOOLEAN, FALSE by default)
- `is_rejected` (BOOLEAN, FALSE by default)
- `rejection_reason` (TEXT)

### Storage Configuration (Already Set)
The `driver_licenses` bucket has RLS policies:
- **INSERT**: Authenticated users + anon users can upload
- **SELECT**: Admins can view all, users can view own files
- **UPDATE**: Authenticated users can update own files

## User Experience

### New Driver Registration
1. **Register** → Fills form (no license upload) → Confirms email
2. **Login** → System checks `license_photo_url` is NULL → Auto-redirects to onboarding
3. **Onboarding** → Shows welcome, checklist, license upload widget
4. **Upload License** → Picks photo → System uploads and updates driver record
5. **Completion** → Shows "You're all set!" message
6. **Dashboard** → Can now toggle online (pending admin approval)

### Existing Drivers (Already Registered Before This Feature)
- If they have `license_photo_url` populated, they bypass onboarding
- They proceed directly to dashboard on login
- No changes needed for existing approved drivers

### Rejected Drivers (Can Resubmit)
- Still use `driver_license_resubmit.dart` flow
- Can reupload license and reset approval status
- After resubmission, still need admin re-approval

## Blocking Rules

### Cannot Go Online If:
1. `license_photo_url` is NULL (triggers "License Not Uploaded" dialog)
2. `is_approved` is FALSE (triggers "Approval Pending" or "Rejection" dialog)
3. `is_rejected` is TRUE (triggers rejection dialog with reason)

### Flow for Rejected License
1. Driver sees "Registration Rejected" dialog on toggle
2. Button: "Resubmit License" → Navigates to `driver_license_resubmit.dart`
3. Can upload new license and reset approval status
4. Goes back into approval queue

## Testing Checklist

- [ ] New driver registers without license upload
- [ ] Email confirmation required (auth check)
- [ ] Login after confirmation → redirects to onboarding
- [ ] Onboarding page displays checklist
- [ ] Can select license photo from gallery
- [ ] Photo uploads to `driver_licenses` bucket
- [ ] `drivers.license_photo_url` updated with public URL
- [ ] Checklist item marks as completed
- [ ] "Go to Dashboard" button navigates to driver dashboard
- [ ] Dashboard shows toggleable online status (pending approval)
- [ ] Cannot go online if license is missing (shows dialog)
- [ ] Cannot go online if approval is pending
- [ ] Existing drivers with license_photo_url bypass onboarding
- [ ] Rejected drivers can resubmit via rejection dialog button

## Troubleshooting

### Driver Stuck in Onboarding
- **Cause**: Camera roll permissions not granted
- **Fix**: Check app permissions in device settings

### Upload Fails with 403 Forbidden
- **Cause**: User not authenticated or storage bucket misconfigured
- **Fix**: Verify email confirmation is complete and RLS policies are correct

### Can't Toggle Online After License Upload
- **Cause**: `is_approved` is still FALSE (admin hasn't approved yet)
- **Fix**: Check admin dashboard for pending driver approvals

### Onboarding Bypassed for New Driver
- **Cause**: `license_photo_url` is not NULL in DB
- **Fix**: Verify driver record was created with NULL license_photo_url

## Related Documentation
- [STORAGE_BUCKET_SETUP.md](STORAGE_BUCKET_SETUP.md) - Storage RLS policies
- [DRIVER_APPROVAL_TROUBLESHOOTING.md](DRIVER_APPROVAL_TROUBLESHOOTING.md) - Approval system issues
- [DRIVER_LICENSE_VERIFICATION_SETUP.md](DRIVER_LICENSE_VERIFICATION_SETUP.md) - License verification system
