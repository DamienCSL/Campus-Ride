// lib/driver_notifications.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'notification_service.dart';

class DriverNotificationsPage extends StatefulWidget {
  const DriverNotificationsPage({Key? key}) : super(key: key);

  @override
  State<DriverNotificationsPage> createState() => _DriverNotificationsPageState();
}

class _DriverNotificationsPageState extends State<DriverNotificationsPage> {
  final supabase = Supabase.instance.client;
  final NotificationService _notificationService = NotificationService();
  
  List<Map<String, dynamic>> _notifications = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadNotifications();
    _subscribeToNotifications();
  }

  Future<void> _loadNotifications() async {
    try {
      final notifications = await _notificationService.getNotifications(limit: 100);
      if (mounted) {
        setState(() {
          _notifications = notifications;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading notifications: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _subscribeToNotifications() {
    _notificationService.notificationStream.listen((notification) {
      if (mounted) {
        setState(() {
          _notifications.insert(0, notification);
        });
      }
    });
  }

  Future<void> _markAsRead(String notificationId) async {
    try {
      await _notificationService.markAsRead(notificationId);
      if (mounted) {
        setState(() {
          final index = _notifications.indexWhere((n) => n['id'] == notificationId);
          if (index != -1) {
            _notifications[index]['read'] = true;
          }
        });
      }
    } catch (e) {
      debugPrint('Error marking notification as read: $e');
    }
  }

  String _getNotificationIcon(String type) {
    switch (type) {
      case 'system':
        return '📬';
      case 'ride':
        return '🚗';
      case 'chat':
        return '💬';
      case 'support':
        return '🆘';
      default:
        return '📬';
    }
  }

  Color _getNotificationColor(String type) {
    const campusGreen = Color(0xFF00BFA6);
    switch (type) {
      case 'system':
        if (_notifications.isNotEmpty) {
          final data = _notifications.firstWhere((n) => n['type'] == type)['data'];
          if (data != null && data['approved'] == 'true') {
            return Colors.green;
          }
          if (data != null && data['rejected'] == 'true') {
            return Colors.red;
          }
        }
        return Colors.blue;
      case 'ride':
        return campusGreen;
      case 'chat':
        return Colors.blue;
      case 'support':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    const campusGreen = Color(0xFF00BFA6);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        backgroundColor: campusGreen,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _notifications.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.notifications_none, size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text(
                        'No notifications yet',
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'You\'ll receive notifications about your registration status here',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _notifications.length,
                  itemBuilder: (context, index) {
                    final notification = _notifications[index];
                    final isRead = notification['read'] as bool? ?? false;
                    final type = notification['type'] as String? ?? 'general';
                    final icon = _getNotificationIcon(type);
                    final color = _getNotificationColor(type);

                    return Dismissible(
                      key: Key(notification['id']),
                      background: Container(
                        color: Colors.red.shade300,
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 16),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (_) async {
                        setState(() => _notifications.removeAt(index));
                        // Optionally delete from database
                        try {
                          await supabase
                              .from('notifications')
                              .delete()
                              .eq('id', notification['id']);
                        } catch (e) {
                          debugPrint('Error deleting notification: $e');
                        }
                      },
                      child: InkWell(
                        onTap: () {
                          if (!isRead) {
                            _markAsRead(notification['id']);
                          }
                        },
                        child: Container(
                          color: isRead ? Colors.white : Colors.blue.shade50,
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                icon,
                                style: const TextStyle(fontSize: 28),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            notification['title'] as String? ?? 'Notification',
                                            style: TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.black87,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (!isRead)
                                          Container(
                                            width: 8,
                                            height: 8,
                                            decoration: BoxDecoration(
                                              color: color,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      notification['body'] as String? ?? '',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey[700],
                                      ),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      _formatTime(notification['created_at']),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[500],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (!isRead)
                                Padding(
                                  padding: const EdgeInsets.only(left: 8),
                                  child: Icon(Icons.circle, size: 12, color: color),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  String _formatTime(String? createdAt) {
    if (createdAt == null) return '';
    try {
      final time = DateTime.parse(createdAt);
      final now = DateTime.now();
      final difference = now.difference(time);

      if (difference.inSeconds < 60) {
        return 'Just now';
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours}h ago';
      } else if (difference.inDays < 7) {
        return '${difference.inDays}d ago';
      } else {
        return 'Long ago';
      }
    } catch (e) {
      return '';
    }
  }
}
