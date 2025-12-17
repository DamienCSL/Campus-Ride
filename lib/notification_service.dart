// lib/notification_service.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final supabase = Supabase.instance.client;
  RealtimeChannel? _subscription;
  
  final StreamController<Map<String, dynamic>> _notificationController =
      StreamController<Map<String, dynamic>>.broadcast();
  
  final StreamController<int> _unreadCountController =
      StreamController<int>.broadcast();

  Stream<Map<String, dynamic>> get notificationStream =>
      _notificationController.stream;
  
  Stream<int> get unreadCountStream => _unreadCountController.stream;

  int _unreadCount = 0;
  int get unreadCount => _unreadCount;

  /// Initialize the notification service and subscribe to realtime updates
  Future<void> initialize() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    // Load initial unread count
    await _loadUnreadCount();

    // Subscribe to realtime notifications
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
            final newNotification = payload.newRecord;
            _notificationController.add(newNotification);
            _unreadCount++;
            _unreadCountController.add(_unreadCount);
          },
        )
        .subscribe();
  }

  /// Load unread notification count from database
  Future<void> _loadUnreadCount() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final response = await supabase
          .from('notifications')
          .select('id')
          .eq('user_id', userId)
          .eq('read', false);
      
      _unreadCount = (response as List).length;
      _unreadCountController.add(_unreadCount);
    } catch (e) {
      debugPrint('Error loading unread count: $e');
    }
  }

  /// Create a new notification
  Future<void> createNotification({
    required String userId,
    required String title,
    required String body,
    String type = 'general',
    Map<String, dynamic>? data,
  }) async {
    try {
      await supabase.from('notifications').insert({
        'user_id': userId,
        'title': title,
        'body': body,
        'type': type,
        'data': data,
        'read': false,
        'created_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error creating notification: $e');
    }
  }

  /// Get all notifications for current user
  Future<List<Map<String, dynamic>>> getNotifications({
    int limit = 50,
    int offset = 0,
  }) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return [];

    try {
      final response = await supabase
          .from('notifications')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error fetching notifications: $e');
      return [];
    }
  }

  /// Mark a notification as read
  Future<void> markAsRead(String notificationId) async {
    try {
      await supabase
          .from('notifications')
          .update({'read': true})
          .eq('id', notificationId);

      if (_unreadCount > 0) {
        _unreadCount--;
        _unreadCountController.add(_unreadCount);
      }
    } catch (e) {
      debugPrint('Error marking notification as read: $e');
    }
  }

  /// Mark all notifications as read
  Future<void> markAllAsRead() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await supabase
          .from('notifications')
          .update({'read': true})
          .eq('user_id', userId)
          .eq('read', false);

      _unreadCount = 0;
      _unreadCountController.add(_unreadCount);
    } catch (e) {
      debugPrint('Error marking all as read: $e');
    }
  }

  /// Delete a notification
  Future<void> deleteNotification(String notificationId) async {
    try {
      await supabase.from('notifications').delete().eq('id', notificationId);
    } catch (e) {
      debugPrint('Error deleting notification: $e');
    }
  }

  /// Clean up resources
  void dispose() {
    _subscription?.unsubscribe();
    _notificationController.close();
    _unreadCountController.close();
  }
}
