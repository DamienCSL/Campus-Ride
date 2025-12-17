# Driver Approval/Rejection Notification System

## Overview
Drivers receive real-time notifications when their registration is approved or rejected by admin. Notifications appear as animated overlays and are stored in the database.

## Architecture

### Notification Flow
```
Admin Approves/Rejects Driver → AdminDriverApprovalPage sends notification → 
Supabase notifications table updated → Real-time listener on driver device → 
NotificationOverlay displays on screen
```

### Components

#### 1. **NotificationService** (Singleton)
- **Location**: `lib/notification_service.dart`
- **Responsibilities**:
  - Subscribes to realtime notification updates via Supabase
  - Creates new notifications in database
  - Manages unread notification count
  - Broadcasts notifications through streams
- **Key Methods**:
  - `initialize()`: Subscribe to driver's realtime notifications
  - `createNotification()`: Create notification in database (used by admin)
  - `notificationStream`: Stream of new notifications for UI
  - `unreadCountStream`: Stream of unread count updates

#### 2. **NotificationOverlay** (Widget)
- **Location**: `lib/notification_overlay.dart`
- **Responsibilities**:
  - Listens to notification stream
  - Animates notification slide-down from top
  - Displays notification title, body, and icon
  - Auto-hides after 4 seconds
- **Features**:
  - Slide animation (500ms down, 4s visible, 500ms up)
  - Color-coded by type (ride=teal, approval=green, rejection=red, etc.)
  - Icon emoji based on notification type
- **Wrapped in**: `DriverDashboard` body

#### 3. **AdminDriverApprovalPage** (Approval Source)
- **Location**: `lib/admin_driver_approval.dart`
- **Sends Notifications**:
  - **On Approve**: "Registration Approved" → Driver can now go online
  - **On Reject**: "Registration Rejected" → Shows rejection reason
- **Notification Calls**:
  ```dart
  // Approval notification
  NotificationService().createNotification(
    userId: driverId,
    title: 'Registration Approved',
    body: 'Congratulations! Your driver registration has been approved. You can now start accepting rides.',
    type: 'system',
    data: {'approved': 'true'},
  );

  // Rejection notification
  NotificationService().createNotification(
    userId: driverId,
    title: 'Registration Rejected',
    body: 'Your driver registration has been rejected. Reason: $reason',
    type: 'system',
    data: {'rejected': 'true', 'reason': reason},
  );
  ```

#### 4. **DriverDashboard** (Notification Listener)
- **Location**: `lib/driver_dashboard.dart`
- **Initialization** (in `initState`):
  ```dart
  NotificationService().initialize();
  ```
- **Wraps UI** with `NotificationOverlay` to display notifications

#### 5. **DriverOnboarding** (Notification Listener)
- **Location**: `lib/driver_onboarding.dart`
- **Initialization** (in `initState`):
  ```dart
  NotificationService().initialize();
  ```
- **Allows drivers to see approval/rejection notifications while uploading license**

### Database Schema

**notifications** table:
```sql
CREATE TABLE notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  type TEXT DEFAULT 'general', -- 'system', 'ride', 'chat', 'support', etc.
  data JSONB, -- Additional context (e.g., {'approved': 'true'})
  read BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT now(),
  INDEX (user_id, read)
);
```

## User Experience

### Driver Receives Approval Notification
1. Admin clicks "Approve" on driver in AdminDriverApprovalPage
2. System:
   - Updates `drivers.is_approved = true` in database
   - Creates notification record with title "Registration Approved"
3. Driver device (if online):
   - Realtime listener receives notification event
   - Triggers slide-down animation at top of screen
   - Shows "✅ Registration Approved" + body text
   - Auto-hides after 4 seconds
4. Driver can now:
   - Toggle online status on dashboard
   - Start accepting rides

### Driver Receives Rejection Notification
1. Admin clicks "Reject" + enters reason on driver detail
2. System:
   - Updates `drivers.is_rejected = true` in database
   - Saves rejection_reason
   - Creates notification record with reason in body
3. Driver device (if online):
   - Realtime listener receives notification
   - Triggers slide-down animation
   - Shows "❌ Registration Rejected" + reason text
   - Auto-hides after 4 seconds
4. Driver receives dialog on next dashboard toggle attempt:
   - Shows rejection reason
   - Offers "Resubmit License" button
   - Can navigate to license upload page

## Notification Types & Display

| Type | Icon | Color | Message |
|------|------|-------|---------|
| system (approval) | ✅ | Green | "Registration Approved" |
| system (rejection) | ❌ | Red | "Registration Rejected" |
| ride | 🚗 | Teal | Ride-related notifications |
| chat | 💬 | Blue | Chat messages |
| support | 🆘 | Orange | Support requests |
| general | 📬 | Gray | Other notifications |

## Real-time Implementation

### Supabase Realtime Channel
```dart
_subscription = supabase
    .channel('notifications:$userId')
    .onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'notifications',
      filter: PostgresChangeFilter(
        type: PostgresChangeFilterType.eq,
        column: 'user_id',
        value: userId,
      ),
      callback: (payload) {
        // New notification inserted in DB
        // NotificationOverlay will animate it
      },
    )
    .subscribe();
```

## Testing Checklist

- [ ] Admin approves driver → Driver sees "Registration Approved" notification
- [ ] Approval notification shows on driver dashboard in real-time
- [ ] Approval notification shows on onboarding screen if driver is there
- [ ] After approval, driver can toggle online status
- [ ] Admin rejects driver with reason → Driver sees "Registration Rejected" notification
- [ ] Rejection notification displays reason text
- [ ] Rejection notification triggers rejection dialog on dashboard
- [ ] Notification slides down from top
- [ ] Notification auto-hides after 4 seconds
- [ ] Multiple notifications queue properly (don't overlap)
- [ ] Notifications persist to database (visible in notifications table)
- [ ] Unread count updates when new notification arrives
- [ ] Notification service initializes on both dashboard and onboarding pages

## Troubleshooting

### Driver Not Receiving Notification
- **Cause**: NotificationService not initialized or network issue
- **Fix**: Ensure `NotificationService().initialize()` is called in driver page initState

### Notification Appears But Doesn't Disappear
- **Cause**: Animation controller issue or mounted state problem
- **Fix**: Check console for errors; verify NotificationOverlay is properly disposed

### Notifications Not Real-time
- **Cause**: Supabase realtime channel not subscribed or permissions issue
- **Fix**: Check database RLS policy allows inserts to notifications table; verify auth token valid

### Wrong Notification Type Icon/Color
- **Cause**: Notification type not handled in `_getNotificationColor()` or `_getNotificationIcon()`
- **Fix**: Add type to switch statement in notification_overlay.dart

## Related Documentation
- [ADMIN_SETUP_GUIDE.md](ADMIN_SETUP_GUIDE.md) - Admin dashboard setup
- [DRIVER_APPROVAL_TROUBLESHOOTING.md](DRIVER_APPROVAL_TROUBLESHOOTING.md) - Approval system issues
- [ONBOARDING_SETUP.md](ONBOARDING_SETUP.md) - Onboarding flow with notifications
