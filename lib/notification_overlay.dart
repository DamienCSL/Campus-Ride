// lib/notification_overlay.dart
import 'package:flutter/material.dart';
import 'notification_service.dart';

class NotificationOverlay extends StatefulWidget {
  final Widget child;

  const NotificationOverlay({
    Key? key,
    required this.child,
  }) : super(key: key);

  @override
  State<NotificationOverlay> createState() => _NotificationOverlayState();
}

class _NotificationOverlayState extends State<NotificationOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;
  final NotificationService _notificationService = NotificationService();

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));

    // Listen to notifications
    _notificationService.notificationStream.listen((notification) {
      _showNotificationSlide(notification);
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _showNotificationSlide(Map<String, dynamic> notification) async {
    if (!mounted) return;

    // Play slide down animation
    await _animationController.forward();

    // Keep visible for 4 seconds
    await Future.delayed(const Duration(seconds: 4));

    // Slide up and out
    await _animationController.reverse();
  }

  String _getNotificationIcon(String type) {
    switch (type) {
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
    return Stack(
      children: [
        widget.child,
        // Notification overlay
        StreamBuilder<Map<String, dynamic>>(
          stream: _notificationService.notificationStream,
          builder: (context, snapshot) {
            if (!snapshot.hasData) {
              return const SizedBox.shrink();
            }

            final notification = snapshot.data!;
            final title = notification['title'] ?? 'New Notification';
            final body = notification['body'] ?? '';
            final type = notification['type'] ?? 'general';

            return Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SlideTransition(
                position: _slideAnimation,
                child: Container(
                  decoration: BoxDecoration(
                    color: _getNotificationColor(type),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: EdgeInsets.fromLTRB(
                    16,
                    MediaQuery.of(context).padding.top + 12,
                    16,
                    12,
                  ),
                  child: Row(
                    children: [
                      Text(
                        _getNotificationIcon(type),
                        style: const TextStyle(fontSize: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (body.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                body,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withOpacity(0.9),
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
