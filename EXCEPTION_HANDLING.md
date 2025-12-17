# Exception Handling System - CampusRide

This document describes the comprehensive exception handling system implemented in the CampusRide app.

## Overview

The app uses a centralized `ErrorHandler` class (`lib/error_handler.dart`) to manage all exceptions consistently across the application.

## Key Components

### 1. AppException Class

A custom exception class for app-specific errors:

```dart
AppException({
  required String message,       // User-friendly error message
  String? code,                  // Error code for debugging
  dynamic originalError,         // Original exception object
})
```

**Usage:**
```dart
throw AppException(
  message: 'Failed to create trip',
  code: 'trip_creation_failed',
);
```

### 2. ErrorHandler Utility Class

Centralized error handling with the following methods:

#### `getErrorMessage(dynamic error)`
Converts any exception into a user-friendly message:
- `AuthException` → Authentication-specific messages
- `PostgrestException` → Database-specific messages  
- `AppException` → Custom app messages
- Other exceptions → Generic fallback

**Example Messages:**
- Invalid credentials → "Invalid email or password. Please try again."
- Duplicate key → "An account with this email already exists."
- Network error → "Network error. Please check your internet connection."

#### `showErrorSnackBar(BuildContext context, dynamic error)`
Displays a red error snackbar with auto-dismiss and close button:
```dart
try {
  await _login();
} catch (e) {
  ErrorHandler.showErrorSnackBar(context, e);
}
```

#### `showSuccessSnackBar(BuildContext context, String message)`
Displays a green success message:
```dart
ErrorHandler.showSuccessSnackBar(context, 'Registration successful!');
```

#### `showInfoSnackBar(BuildContext context, String message)`
Displays a blue info message:
```dart
ErrorHandler.showInfoSnackBar(context, 'Please wait...');
```

#### `logError(String source, dynamic error, [StackTrace? stackTrace])`
Logs detailed error information for debugging:
```dart
ErrorHandler.logError('login', e, stackTrace);
// Output:
// === ERROR in login ===
// Error: [error details]
// StackTrace: [stack trace]
// ========================
```

## Implementation in Files

### 1. **login.dart**
- Input validation before API calls
- Specific handling for AuthException and PostgrestException
- Mounted checks before setState
- Detailed error logging

**Key Updates:**
```dart
Future<void> _login() async {
  final email = emailCtrl.text.trim();
  
  // Validation
  if (email.isEmpty) {
    ErrorHandler.showErrorSnackBar(context, 'Please fill in all fields');
    return;
  }

  try {
    // API call
  } on AuthException catch (e) {
    ErrorHandler.logError('login', e);
    ErrorHandler.showErrorSnackBar(context, e);
  }
}
```

### 2. **register.dart**
- Comprehensive input validation
- Auth and database error handling
- Success confirmation before navigation
- Profile creation error handling

**Key Updates:**
```dart
try {
  final res = await supabase.auth.signUp(email: email, password: password);
  
  // ... profile creation
  
  if (!mounted) return;
  ErrorHandler.showSuccessSnackBar(context, 'Registration successful!');
} on PostgrestException catch (e) {
  ErrorHandler.showErrorSnackBar(context, AppException(
    message: 'Failed to create profile',
    code: 'profile_creation_failed',
    originalError: e,
  ));
}
```

### 3. **driver_register.dart**
- All registration fields validated
- Driver, profile, and vehicle creation error handling
- Specific error messages for different failure scenarios
- Proper cleanup in finally block

**Key Updates:**
```dart
try {
  // 1. Profile insert
  // 2. Driver insert
  // 3. Vehicle insert
  
  ErrorHandler.showSuccessSnackBar(context, 'Driver registered successfully!');
} on PostgrestException catch (e) {
  String errorMsg = 'Failed to complete driver registration';
  if (e.message.contains('duplicate')) {
    errorMsg = 'This information already exists in our system';
  }
  ErrorHandler.showErrorSnackBar(context, AppException(
    message: errorMsg,
    code: 'driver_registration_failed',
    originalError: e,
  ));
} finally {
  if (mounted) {
    setState(() => _isLoading = false);
  }
}
```

### 4. **book_trip.dart**
- Trip creation error handling
- Google Maps API error handling
- Location service errors
- Database operation error handling

**Key Updates:**
```dart
Future<String?> _saveTripToSupabase() async {
  try {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      throw AppException(
        message: 'User not authenticated',
        code: 'no_auth',
      );
    }
    // ... insert trip
  } on PostgrestException catch (e) {
    ErrorHandler.logError('_saveTripToSupabase', e);
  }
}
```

## Error Categories & Handling

### Authentication Errors
```
- "invalid login credentials" → "Invalid email or password"
- "user already exists" → "Account already exists"
- "email not confirmed" → "Please verify your email"
- "weak password" → "Password must be at least 6 characters"
- "invalid email" → "Please enter a valid email"
```

### Database Errors
```
- "permission denied" → "You do not have permission"
- "duplicate key" → "This record already exists"
- "foreign key violation" → "Invalid reference to related data"
- "not found" → "The requested data was not found"
- "constraint violation" → "Invalid data provided"
```

### Network Errors
```
- "connection refused" → "Network error. Check your connection"
- "timeout" → "Request timed out. Please try again"
```

## Best Practices

### 1. Always Use try-catch-finally
```dart
try {
  // Async operation
  await operation();
} on SpecificException catch (e) {
  // Handle specific exception type
  ErrorHandler.logError('source', e);
  ErrorHandler.showErrorSnackBar(context, e);
} catch (e) {
  // Handle generic exception
  ErrorHandler.showErrorSnackBar(context, e);
} finally {
  // Cleanup: cancel timers, close streams, etc.
  if (mounted) {
    setState(() => _isLoading = false);
  }
}
```

### 2. Check mounted Before setState
```dart
try {
  await asyncOperation();
} catch (e) {
  if (!mounted) return;  // Prevent setState after dispose
  ErrorHandler.showErrorSnackBar(context, e);
}

finally {
  if (mounted) {
    setState(() => _isLoading = false);
  }
}
```

### 3. Log Errors for Debugging
```dart
ErrorHandler.logError('function_name', error, stackTrace);
// Helps with debugging without showing raw errors to users
```

### 4. Use AppException for Custom Errors
```dart
throw AppException(
  message: 'User-friendly message',
  code: 'error_code_for_logging',
  originalError: originalException,
);
```

### 5. Validate Input Before API Calls
```dart
if (email.isEmpty) {
  ErrorHandler.showErrorSnackBar(context, 'Email is required');
  return;
}
```

## Files Updated

1. ✅ `lib/error_handler.dart` - NEW: Centralized error handling system
2. ✅ `lib/login.dart` - Auth error handling with detailed messages
3. ✅ `lib/register.dart` - Registration validation and error handling
4. ✅ `lib/driver_register.dart` - Multi-step driver registration error handling
5. ✅ `lib/book_trip.dart` - Trip creation error handling with proper cleanup

## Future Enhancements

1. Add crash reporting (Firebase Crashlytics integration)
2. Implement retry logic for failed network requests
3. Add offline error handling for connectivity issues
4. Create an error analytics dashboard
5. Add localization for error messages
6. Implement error recovery strategies

## Testing

To test error handling:

1. **Authentication Errors:**
   - Try logging in with invalid credentials
   - Try registering with existing email
   - Use weak passwords

2. **Database Errors:**
   - Try creating duplicate records
   - Test with RLS permission issues
   - Try operations with missing data

3. **Network Errors:**
   - Disconnect internet and try API calls
   - Use slow network simulator
   - Test with request timeouts

4. **Edge Cases:**
   - Navigate away during API call (test mounted checks)
   - Close app during operation
   - Test with null values

## Troubleshooting

### Common Issues

**Issue: "Unused import: error_handler.dart"**
- The error is shown in files importing ErrorHandler but using it in future phases
- This is safe to ignore as it will be used as more features are implemented

**Issue: Error messages not showing**
- Ensure `ScaffoldMessenger` is available in the widget tree
- Check if `if (!mounted) return;` is blocking the error display
- Verify error handling code is in a try-catch block

**Issue: Multiple error snackbars showing**
- Only one snackbar can be shown at a time
- Previous snackbars are auto-replaced by new ones (default Flutter behavior)

## References

- [Supabase Exception Documentation](https://pub.dev/documentation/supabase/latest/supabase/PostgrestException-class.html)
- [Flutter Error Handling Best Practices](https://flutter.dev/docs/testing/errors)
- [Dart Exception Handling](https://dart.dev/guides/language/language-tour#exceptions)
