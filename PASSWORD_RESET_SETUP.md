# Password Reset Flow Setup

## Overview
This guide walks through setting up the forgot password and reset password functionality for CampusRide. The flow is:

1. User enters email on **Forgot Password** page
2. Supabase sends password reset email
3. User clicks link in email (opens reset password page)
4. User enters new password
5. Password is updated and user returns to login

---

## ✅ What's Implemented

### Frontend Components
- **forgot_password.dart**: Request password reset by email
- **reset_password.dart**: Enter new password after clicking email link
- **login.dart**: "Forgot Password?" link to forgot password page
- **main.dart**: Deep link handling for email links

### Features
- ✅ Timeout protection (10-15 seconds)
- ✅ Loading states with spinner
- ✅ Success/error messaging
- ✅ Email validation
- ✅ Password strength validation (min 6 chars)
- ✅ Confirm password matching
- ✅ Deep link detection for email links
- ✅ Debug logging with emojis

---

## 📧 Supabase Email Configuration

### Step 1: Enable Email Provider in Supabase
1. Go to [Supabase Dashboard](https://supabase.com/dashboard)
2. Select your **CampusRide** project
3. Go to **Authentication** → **Providers**
4. Make sure **Email** is enabled

### Step 2: Configure Email Templates
1. Go to **Authentication** → **Email Templates**
2. Find **Reset Password** template
3. Customize the email template:

**Default Template:**
```
<h2>Reset your password</h2>
<p>Follow this link to reset your password:</p>
<p><a href="{{ .SiteURL }}/auth/v1/verify?token={{ .Token }}&type=recovery&redirect_to={{ .RedirectTo }}">Reset Password</a></p>
```

**For Mobile App (Recommended):**
```
<h2>Reset Your CampusRide Password</h2>
<p>We received a request to reset your password. Click the link below to proceed:</p>
<a href="io.campusride://reset-password?token={{ .Token }}" style="background-color: #00BFA6; color: white; padding: 10px 20px; text-decoration: none; border-radius: 4px; display: inline-block;">
  Reset Password
</a>
<p>If you didn't request this, please ignore this email.</p>
<p>This link will expire in 1 hour.</p>
```

### Step 3: Update Deep Link Configuration

#### For Android (android/app/build.gradle)
Add this in your app's `build.gradle.kts`:

```kotlin
android {
    ...
    defaultConfig {
        ...
        // Add this after applicationId
        manifestPlaceholders = [
            "appAuthRedirectScheme": "io.campusride"
        ]
    }
}
```

#### Update AndroidManifest.xml (android/app/src/main/AndroidManifest.xml)

Add this intent filter to the MainActivity:

```xml
<activity
    android:name=".MainActivity"
    android:launchMode="singleTop"
    ...
>
    <intent-filter>
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data
            android:scheme="io"
            android:host="campusride"
            android:pathPrefix="/reset-password" />
    </intent-filter>
</activity>
```

#### For iOS (ios/Runner/Info.plist)

Add URL Scheme configuration:

```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLName</key>
        <string>io.campusride</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>io.campusride</string>
        </array>
    </dict>
</array>
```

### Step 4: Test the Flow

**Test Email Address:**
1. Go to Supabase Dashboard → Authentication → Users
2. Create a test user or use an existing one
3. Note their email address

**Trigger Reset Email:**
1. Run your app
2. Click "Forgot Password?" on login page
3. Enter the test email
4. You should see: "✅ [ForgotPassword] Reset email sent successfully"
5. Check Supabase email logs or your email inbox

**Verify Email Reception:**
- Check your email inbox for reset link
- Link format: `io.campusride://reset-password?token=<token>`

**Click Link:**
- On Android/iOS: Clicking the link should open the app and navigate to ResetPasswordPage
- On Web: You can manually copy the token and navigate

---

## 🔍 Testing Checklist

### Forgot Password Page
- [ ] Can navigate to Forgot Password from Login
- [ ] Email validation works
- [ ] Shows loading spinner while sending
- [ ] Success message shows after email sent
- [ ] Can go back to login

### Reset Password Page
- [ ] Can navigate after clicking email link
- [ ] Password must be ≥ 6 characters
- [ ] Passwords must match
- [ ] Show/hide password toggle works
- [ ] Loading spinner shows while resetting
- [ ] Success message appears after reset
- [ ] "Back to Login" button works

### Full Flow
- [ ] Send email works (check Supabase logs)
- [ ] Email arrives in inbox (may take 1-2 min)
- [ ] Click link opens app to reset page
- [ ] Reset with new password works
- [ ] Can login with new password
- [ ] Old password no longer works

---

## 📊 Database Queries to Check

### View password reset attempts:
```sql
-- Check auth logs (if enabled)
SELECT * FROM auth.audit_log_entries 
WHERE action = 'recovery_requested' 
ORDER BY created_at DESC 
LIMIT 10;
```

### Check user sessions:
```sql
SELECT id, email, last_sign_in_at, updated_at
FROM auth.users 
ORDER BY updated_at DESC 
LIMIT 10;
```

---

## 🐛 Debugging

### Check Logs
Open **Logcat** (Android) or **Console** (iOS) and look for:

```
🔐 [ForgotPassword] Sending reset email to: user@example.com
✅ [ForgotPassword] Reset email sent successfully
📧 [Login] Attempting login for: user@example.com
✅ [Login] Sign in successful
🔄 [ResetPassword] Resetting password...
✅ [ResetPassword] Password reset successfully
```

### Common Issues

**"⚠️ [Main] Profile fetch timeout"**
- This is OK - means Supabase was slow but password reset still worked

**"❌ [ForgotPassword] Error: invalid_grant"**
- Session expired or invalid token
- User needs to be logged out first

**Email not arriving:**
1. Check spam folder
2. Verify email in Supabase Users list is correct
3. Check Supabase → Project Settings → Email Templates → Recent Logs

**Deep link not opening app:**
1. Check AndroidManifest.xml is correct
2. Try: `adb shell am start -W -a android.intent.action.VIEW -d "io.campusride://reset-password" io.campusride`
3. On iOS, check Info.plist configuration

---

## 📱 User Instructions

### For Users/Drivers
1. Click "Forgot Password?" on login screen
2. Enter your email address
3. Click "Send Reset Link"
4. Check your email inbox (may take 1-2 minutes)
5. Click the "Reset Password" link in the email
6. Enter your new password and confirm
7. Click "Reset Password"
8. You'll be redirected to login
9. Log in with your new password

---

## 🔐 Security Notes
- Reset links expire after 1 hour
- Passwords are hashed using bcrypt in Supabase
- Only the user who requested the reset can use the link
- Failed attempts are logged in audit log
- Rate limiting prevents brute force attacks

---

## 📚 References
- [Supabase Auth Documentation](https://supabase.com/docs/guides/auth)
- [Supabase Email Templates](https://supabase.com/docs/guides/auth/email-templates)
- [Flutter Deep Linking](https://flutter.dev/docs/development/ui/navigation/deep-linking)
