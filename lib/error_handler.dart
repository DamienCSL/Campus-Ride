// lib/error_handler.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Custom exception class for app-specific errors
class AppException implements Exception {
  final String message;
  final String? code;
  final dynamic originalError;

  AppException({
    required this.message,
    this.code,
    this.originalError,
  });

  @override
  String toString() => 'AppException: $message (Code: $code)';
}

/// Centralized error handler
class ErrorHandler {
  static String getErrorMessage(dynamic error) {
    if (error is AuthException) {
      return _handleAuthException(error);
    } else if (error is PostgrestException) {
      return _handlePostgrestException(error);
    } else if (error is AppException) {
      return error.message;
    } else if (error is Exception) {
      return error.toString();
    }
    return 'An unexpected error occurred: $error';
  }

  static String _handleAuthException(AuthException error) {
    final message = error.message.toLowerCase();

    if (message.contains('invalid login credentials')) {
      return 'Invalid email or password. Please try again.';
    } else if (message.contains('user already exists')) {
      return 'An account with this email already exists.';
    } else if (message.contains('email not confirmed')) {
      return 'Please verify your email address.';
    } else if (message.contains('weak password')) {
      return 'Password must be at least 6 characters.';
    } else if (message.contains('invalid email')) {
      return 'Please enter a valid email address.';
    } else if (message.contains('connection refused')) {
      return 'Network error. Please check your internet connection.';
    } else if (message.contains('timeout')) {
      return 'Request timed out. Please try again.';
    }

    return 'Authentication error: ${error.message}';
  }

  static String _handlePostgrestException(PostgrestException error) {
    final message = error.message.toLowerCase();

    if (message.contains('permission denied')) {
      return 'You do not have permission to perform this action.';
    } else if (message.contains('duplicate key')) {
      return 'This record already exists.';
    } else if (message.contains('foreign key violation')) {
      return 'Invalid reference to related data.';
    } else if (message.contains('not found')) {
      return 'The requested data was not found.';
    } else if (message.contains('constraint violation')) {
      return 'Invalid data provided.';
    }

    return 'Database error: ${error.message}';
  }

  /// Show error snackbar
  static void showErrorSnackBar(
    BuildContext context,
    dynamic error, {
    Duration duration = const Duration(seconds: 4),
  }) {
    final message = getErrorMessage(error);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: duration,
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  /// Show success snackbar
  static void showSuccessSnackBar(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 2),
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: duration,
      ),
    );
  }

  /// Show info snackbar
  static void showInfoSnackBar(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.blue,
        duration: duration,
      ),
    );
  }

  /// Log error for debugging
  static void logError(String source, dynamic error, [StackTrace? stackTrace]) {
    debugPrint('=== ERROR in $source ===');
    debugPrint('Error: $error');
    if (stackTrace != null) {
      debugPrint('StackTrace: $stackTrace');
    }
    debugPrint('========================');
  }
}
