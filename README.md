# CampusRide - College Campus Ride-Sharing Mobile App

A comprehensive Flutter-based ride-sharing application designed for campus communities, featuring real-time driver tracking, ride management, and admin controls.

## 📋 Features

### For Riders
- 📍 **Real-time Driver Tracking** - Track your driver's location live on Google Maps
- 📱 **Ride Booking** - Easy-to-use interface for booking rides with automatic fare calculation
- ⭐ **Driver Rating System** - Rate and review your drivers after each trip
- 💬 **In-App Chat** - Communicate with your driver before and during the ride
- 🔔 **Notifications** - Get real-time alerts for ride status updates
- 📜 **Trip History** - View all past trips and their details
- 👤 **Profile Management** - Edit profile, change password, manage account

### For Drivers
- 🚗 **Dashboard** - Accept/reject ride requests and manage active trips
- 🗺️ **Navigation** - Turn-by-turn navigation to pickup and destination
- ✅ **Trip Completion** - Complete rides with built-in completion button
- 💰 **Earnings Tracking** - Monitor income with daily/weekly/monthly breakdowns
- 📊 **Performance Metrics** - Track best performing days and earnings trends
- 🎓 **Onboarding** - Tutorial and checklist for driver approval process
- 📋 **License Verification** - Upload and resubmit driver license for admin approval
- 🔔 **Notifications** - Get notified about ride requests and approvals

### For Admins
- 👨‍💼 **Driver Approval** - Review and approve/reject driver applications
- 📸 **License Verification** - View and zoom driver license photos
- 📊 **Analytics Dashboard** - View platform statistics and performance metrics
- 💬 **Support Chat** - Manage user support conversations and close tickets

## 🛠️ Tech Stack

- **Framework**: Flutter 3.8.1+
- **Backend**: Supabase (PostgreSQL + Realtime)
- **Maps**: Google Maps Flutter SDK
- **Location**: Geolocator & Geocoding
- **UI**: Material Design 3
- **Charts**: FL Chart
- **State Management**: setState (StatefulWidget)

## 📦 Prerequisites

### System Requirements
- Flutter SDK 3.8.1 or higher
- Dart 3.0+
- Android Studio/Xcode (for emulator)
- Git

### API Keys Required
- **Google Maps API Key** - For map and direction services
- **Supabase Project** - Backend and authentication

## 🚀 Setup Instructions

### 1. Clone the Repository
```bash
git clone https://github.com/DamienCSL/Campus-Ride.git
cd CampusRide
```

### 2. Install Flutter Dependencies
```bash
flutter pub get
```

### 3. Configure Supabase

#### Create Supabase Project
1. Go to [supabase.com](https://supabase.com) and create a new project
2. Note your Project URL and API Key

#### Set Environment Variables
Update the Google Maps API key in the code (search for `GOOGLE_API_KEY` in navigation files)

### 4. Database Setup

Create the required tables in Supabase SQL Editor:

#### Users & Profiles
```sql
-- profiles table
CREATE TABLE profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id),
  full_name TEXT,
  avatar_url TEXT,
  role TEXT DEFAULT 'rider', -- 'rider', 'driver', 'admin'
  phone TEXT,
  created_at TIMESTAMP DEFAULT NOW()
);
```

#### Drivers
```sql
CREATE TABLE drivers (
  id UUID PRIMARY KEY REFERENCES profiles(id),
  vehicle_id UUID,
  license_photo_url TEXT,
  is_approved BOOLEAN DEFAULT FALSE,
  is_rejected BOOLEAN DEFAULT FALSE,
  rejection_reason TEXT,
  rating DECIMAL(2,1) DEFAULT 0,
  created_at TIMESTAMP DEFAULT NOW()
);
```

#### Rides
```sql
CREATE TABLE rides (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  rider_id UUID REFERENCES profiles(id),
  driver_id UUID REFERENCES drivers(id),
  pickup_lat DECIMAL(10,8),
  pickup_lng DECIMAL(11,8),
  destination_lat DECIMAL(10,8),
  destination_lng DECIMAL(11,8),
  status TEXT DEFAULT 'pending', -- pending, assigned, accepted, arriving, ongoing, completed, cancelled
  estimated_fare DECIMAL(8,2),
  completed_at TIMESTAMP,
  created_at TIMESTAMP DEFAULT NOW()
);
```

#### Notifications
```sql
CREATE TABLE notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES profiles(id),
  title TEXT,
  body TEXT,
  type TEXT,
  data JSONB,
  read BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP DEFAULT NOW()
);
```

#### Reviews
```sql
CREATE TABLE reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ride_id UUID REFERENCES rides(id),
  rider_id UUID REFERENCES profiles(id),
  driver_id UUID REFERENCES drivers(id),
  rating INT CHECK (rating >= 1 AND rating <= 5),
  comment TEXT,
  created_at TIMESTAMP DEFAULT NOW()
);
```

### 5. Storage Setup

Create storage buckets in Supabase:
- `avatars` - For user profile pictures
- `driver_licenses` - For driver license documents

#### Set RLS Policies for driver_licenses
```sql
-- INSERT policy for authenticated users
CREATE POLICY "Drivers can upload their own license"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'driver_licenses'::text 
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- UPDATE policy
CREATE POLICY "Drivers can update their own license"
ON storage.objects FOR UPDATE
USING (bucket_id = 'driver_licenses'::text AND (storage.foldername(name))[1] = auth.uid()::text)
WITH CHECK (bucket_id = 'driver_licenses'::text AND (storage.foldername(name))[1] = auth.uid()::text);

-- SELECT policy for own files
CREATE POLICY "Drivers can view their own license"
ON storage.objects FOR SELECT
USING (bucket_id = 'driver_licenses'::text AND (storage.foldername(name))[1] = auth.uid()::text);

-- DELETE policy
CREATE POLICY "Drivers can delete their own license"
ON storage.objects FOR DELETE
USING (bucket_id = 'driver_licenses'::text AND (storage.foldername(name))[1] = auth.uid()::text);

-- Admin SELECT policy
CREATE POLICY "Admins can view all licenses"
ON storage.objects FOR SELECT
USING (bucket_id = 'driver_licenses'::text AND EXISTS (SELECT 1 FROM profiles WHERE profiles.id = auth.uid() AND profiles.role = 'admin'));
```

## 🧪 Testing

### Run the Application

#### On Android Emulator
```bash
flutter run
```

#### On Physical Device
```bash
flutter run -d <device_id>
```

### Test Scenarios

#### Rider Flow
1. Launch app → Register as rider
2. Book a ride → Enter pickup and destination
3. See driver assignment and real-time tracking
4. Chat with driver during ride
5. Complete trip and rate driver

#### Driver Flow
1. Register as driver
2. Upload driver license
3. Wait for admin approval
4. Accept ride requests
5. Navigate to pickup and destination
6. Complete ride with button
7. View earnings dashboard

#### Admin Flow
1. Login as admin
2. Review driver license in approval page
3. Approve or reject drivers
4. View analytics dashboard
5. Manage support chat tickets

## 📁 Project Structure

```
lib/
├── main.dart                    # App entry point
├── home.dart                    # Rider home screen
├── login.dart                   # Authentication
├── register.dart                # User registration
├── book_trip.dart               # Ride booking
├── driver_tracking.dart         # Real-time driver tracking
├── rating_dialog.dart           # Rate driver dialog
├── driver_dashboard.dart        # Driver main screen
├── driver_navigation.dart       # Turn-by-turn navigation
├── driver_earnings.dart         # Driver earnings dashboard
├── driver_onboarding.dart       # Driver onboarding flow
├── driver_license_resubmit.dart # License update
├── admin_dashboard.dart         # Admin main screen
├── admin_driver_approval.dart   # Driver approval interface
├── admin_analytics.dart         # Analytics dashboard
├── notification_service.dart    # Push notifications
├── supabase_service.dart        # Supabase configuration
└── error_handler.dart           # Error logging & handling
```

## 🔐 Authentication Flow

1. **Email Verification Required** - Users must confirm their email before signing in
2. **Role-Based Access** - Routes determined by user role (rider/driver/admin)
3. **Session Persistence** - User sessions persist across app restarts
4. **Driver Approval Gate** - Drivers must be approved before going online

## 🔔 Real-time Features

- **Ride Status Updates** - Live updates when ride status changes
- **Driver Location Tracking** - Real-time driver position on map
- **Notifications** - Push alerts for approvals, ride updates, messages
- **Chat Messaging** - Live chat between riders and drivers

## 📊 Database Architecture

### Key Relationships
- `profiles` - All users (riders, drivers, admins)
- `drivers` - Driver-specific data (linked to profiles)
- `rides` - Active/completed rides
- `reviews` - Driver ratings from riders
- `notifications` - Real-time alerts
- `vehicles` - Driver vehicle information

## 🐛 Common Issues & Solutions

### Maps Not Loading
- Verify Google Maps API key is correct
- Enable Maps SDK in Google Cloud Console
- Check API key restrictions

### Supabase Connection Failed
- Verify internet connection
- Check Supabase URL and API key in code
- Ensure Supabase project is active

### Location Services Not Working
- Grant location permissions on device
- Enable GPS/location services
- Check geolocator package permissions in manifest

### RLS Policy Errors
- Verify user is authenticated before queries
- Check role-based policy conditions
- Ensure user has necessary table permissions

## 📝 Development Notes

- **State Management**: Uses `setState` for simplicity; consider `Provider`/`Riverpod` for larger apps
- **Error Handling**: Implement comprehensive error logging in production
- **Performance**: Optimize polyline rendering for smoother map interactions
- **Security**: Never commit API keys; use environment variables

## 🤝 Contributing

1. Create a feature branch
2. Make changes and test thoroughly
3. Commit with descriptive messages
4. Push and create Pull Request

## 📄 License

Private project for Campus Ride system.

## 👥 Support

For issues or questions, check the code comments or create an issue in the repository.

---

**Last Updated**: December 17, 2025
