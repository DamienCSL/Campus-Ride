# Admin Dashboard Setup Guide

## Overview
The admin dashboard provides comprehensive management capabilities for the CampusRide application including driver approvals, support chat management, and analytics/reporting.

## Features

### 1. Driver Approval System
- **View Pending Drivers**: See all driver registration requests awaiting approval
- **Approve Drivers**: Approve qualified drivers to start accepting rides
- **Reject Drivers**: Reject unqualified drivers with a detailed reason
- **Notifications**: Automatic notifications sent to drivers upon approval/rejection
- **Driver Details**: View full driver information including license, vehicle, and contact details

### 2. Support Chat Management
- **View All Support Chats**: Access all user support conversations
- **Chat Status**: Track chat status (Open, In Progress, Resolved, Closed)
- **Unread Indicators**: Visual indicators for chats requiring admin attention
- **User Information**: Quick access to user contact details

### 3. Analytics & Reports
- **Hourly Analysis**: View ride requests by hour (last 24 hours)
- **Daily Analysis**: View ride requests by day of week (last 7 days)
- **Monthly Analysis**: View ride requests by month (last 12 months)
- **Peak Period Detection**: Automatically identifies highest demand periods
- **Summary Stats**: Today, This Week, This Month, and All-Time ride counts
- **Visual Charts**: Interactive bar charts for data visualization

## Database Setup

### Step 1: Run Admin Support Setup
Execute the following SQL file in your Supabase SQL Editor:
```sql
-- File: admin_support_setup.sql
-- This creates support_chats and support_messages tables
```

### Step 2: Run Driver Approval Setup
Execute the following SQL file in your Supabase SQL Editor:
```sql
-- File: admin_driver_approval_setup.sql
-- This adds approval fields to the drivers table
```

### Step 3: Create Admin User
Create an admin user by setting the role in the profiles table:
```sql
UPDATE profiles 
SET role = 'admin' 
WHERE email = 'admin@example.com';
```

## Flutter Dependencies

The admin dashboard requires the `fl_chart` package for analytics visualization. It has been added to `pubspec.yaml`:

```yaml
dependencies:
  fl_chart: ^0.69.0
```

Run `flutter pub get` to install the new dependency.

## Admin Access

### Login as Admin
1. Open the app
2. Login with an account that has `role = 'admin'` in the profiles table
3. You will be automatically redirected to the Admin Dashboard

### Admin Navigation
The admin dashboard provides three main sections:
- **Driver Approvals**: Red badge shows pending count
- **Support Chat**: Access all user support conversations
- **Analytics & Reports**: View ride statistics and trends

## API Endpoints Used

### Driver Approval
- `GET /drivers` - Fetch pending drivers (filtered by is_approved=false, is_rejected=false)
- `UPDATE /drivers` - Approve or reject drivers
- `POST /notifications` - Send approval/rejection notifications

### Support Chat
- `GET /support_chats` - Fetch all support chat sessions with user profiles
- Status tracking for open/in-progress/resolved/closed chats

### Analytics
- `GET /rides` - Fetch all rides with timestamps for analysis
- Client-side processing for hourly/daily/monthly aggregation

## RLS Policies

### Admins Have Full Access
All admin RLS policies check for `role = 'admin'` in the profiles table:

```sql
-- Example admin policy
CREATE POLICY "Admins can view all chats"
ON support_chats FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM profiles 
    WHERE profiles.id = auth.uid() 
    AND profiles.role = 'admin'
  )
);
```

## Features to Implement (Future)

1. **Full Support Chat Implementation**: 
   - Currently shows dialog placeholder
   - Implement real-time messaging with users
   - Add file attachment support

2. **Advanced Analytics**:
   - Revenue reports
   - Driver performance metrics
   - User retention analysis
   - Geographic heat maps

3. **User Management**:
   - Ban/suspend users
   - View user activity logs
   - Manage user roles

4. **System Settings**:
   - Configure fare rates
   - Set service areas
   - Manage system notifications

## Testing

### Test Driver Approval Flow
1. Register as a new driver
2. Login as admin
3. Navigate to Driver Approvals
4. View the pending driver
5. Approve or reject with reason
6. Check driver receives notification

### Test Analytics
1. Create several ride requests at different times
2. Login as admin
3. Navigate to Analytics & Reports
4. Toggle between Hourly/Daily/Monthly views
5. Verify peak period is detected correctly

## Security Notes

- ⚠️ **Never hard-code admin credentials**
- ⚠️ **Always use RLS policies to protect admin endpoints**
- ⚠️ **Regularly audit admin access logs**
- ⚠️ **Use strong passwords for admin accounts**
- ⚠️ **Enable 2FA for admin accounts in production**

## Support

For issues or questions:
1. Check the error logs in Flutter DevTools
2. Review Supabase logs for database errors
3. Verify RLS policies are correctly applied
4. Ensure admin user has correct role in profiles table
