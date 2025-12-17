# Notification System Setup Guide

## Overview
The CampusRide notification system provides real-time in-app notifications for riders and drivers using Supabase Realtime.

## Features
- ✅ Real-time notification delivery via Supabase Realtime
- ✅ Notification bell with unread badge counter
- ✅ Notification history page with swipe-to-delete
- ✅ Mark as read / Mark all as read functionality
- ✅ Different notification types (ride, driver, payment, alert)
- ✅ Automatic notifications for ride events:
  - Driver found/assigned
  - Driver accepted ride
  - Trip started
  - Trip completed

## Setup Instructions

### 1. Create Notifications Table in Supabase

1. Go to your Supabase Dashboard
2. Navigate to **SQL Editor**
3. Copy the contents of `supabase_notifications_table.sql`
4. Paste and run the SQL script

This will:
- Create the `notifications` table
- Set up proper indexes for performance
- Enable Row Level Security (RLS) policies
- Enable Realtime for instant updates

### 2. Verify Table Creation

After running the SQL script, verify:
1. Go to **Table Editor** in Supabase
2. Find the `notifications` table
3. Check that it has these columns:
   - `id` (UUID, Primary Key)
   - `user_id` (UUID, Foreign Key to auth.users)
   - `title` (TEXT)
   - `body` (TEXT)
   - `type` (TEXT)
   - `data` (JSONB)
   - `read` (BOOLEAN)
   - `created_at` (TIMESTAMPTZ)

### 3. Enable Realtime

1. In Supabase Dashboard, go to **Database** > **Replication**
2. Ensure `notifications` table is listed under "Tables"
3. Toggle it ON if not already enabled

### 4. Test the Notification System

Run your Flutter app and test:

**For Riders:**
1. Book a ride
2. Wait for driver assignment
3. Check notification bell icon in top-right (should show badge)
4. Tap bell to view notifications
5. Tap notification to mark as read

**For Drivers:**
1. Go online in driver dashboard
2. Accept a ride request
3. Rider should receive notifications at each status change:
   - "Driver Accepted Your Ride"
   - "Trip Started"
   - "Trip Completed"

## File Structure

```
lib/
├── notification_service.dart      # Core service with Realtime subscriptions
├── notifications_page.dart        # UI for viewing notification history
├── home.dart                      # Updated with notification bell icon
├── book_trip.dart                 # Sends notifications when driver found
└── driver_dashboard.dart          # Sends notifications on ride status changes
```

## Notification Types

- `ride` - Ride-related updates (green icon)
- `driver` - Driver-specific notifications (blue icon)
- `payment` - Payment/fare related (orange icon)
- `alert` - Important alerts (red icon)
- `general` - Other notifications (grey icon)

## How It Works

### Real-time Subscription
When the app starts:
1. `NotificationService().initialize()` is called in `home.dart`
2. Service subscribes to Supabase Realtime channel for user's notifications
3. New notifications trigger instant updates to the notification bell badge

### Creating Notifications
```dart
NotificationService().createNotification(
  userId: 'user-uuid',
  title: 'Trip Started',
  body: 'Your trip has begun. Have a safe journey!',
  type: 'ride',
  data: {'ride_id': '123', 'status': 'ongoing'},
);
```

### Notification Flow
1. Event occurs (driver accepts ride, trip starts, etc.)
2. `NotificationService().createNotification()` is called
3. Notification inserted into Supabase `notifications` table
4. Realtime subscription detects INSERT event
5. Notification stream broadcasts to all listeners
6. UI updates (badge counter increments, new notification appears)

## Troubleshooting

### Notifications not appearing?
- Check Supabase Realtime is enabled for `notifications` table
- Verify RLS policies allow INSERT for service role
- Check browser console/Flutter logs for errors

### Badge not updating?
- Ensure `_initializeNotifications()` is called in home page's `initState()`
- Check that user is authenticated before initializing service

### Old notifications not loading?
- Verify `getNotifications()` query works in Supabase SQL Editor
- Check RLS policy allows SELECT for authenticated user

## Future Enhancements

Potential improvements:
- [ ] Push notifications with Firebase Cloud Messaging (FCM)
- [ ] Notification preferences/settings page
- [ ] Sound/vibration on new notifications
- [ ] Rich notifications with images/actions
- [ ] Notification scheduling for reminders
