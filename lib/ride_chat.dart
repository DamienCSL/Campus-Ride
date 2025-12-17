// lib/ride_chat.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:realtime_client/realtime_client.dart' show RealtimeChannel;
import 'supabase_service.dart';
import 'notification_service.dart';

class RideChatPage extends StatefulWidget {
  final String rideId;
  final String myUserId;
  final String peerUserId;
  final String peerName; // driver name or user name for display

  const RideChatPage({
    Key? key,
    required this.rideId,
    required this.myUserId,
    required this.peerUserId,
    required this.peerName,
  }) : super(key: key);

  @override
  State<RideChatPage> createState() => _RideChatPageState();
}

class _RideChatPageState extends State<RideChatPage> {
  RealtimeChannel? _channel;
  final List<Map<String, dynamic>> messages = [];
  final TextEditingController _ctrl = TextEditingController();
  bool _loading = true;
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _initChat();
  }

  Future<void> _initChat() async {
    // 1) Load message history
    try {
      final hist = await SupabaseService.fetchMessages(widget.rideId);
      debugPrint('✅ Loaded ${hist.length} messages for ride ${widget.rideId}');
      setState(() {
        messages.addAll(hist);
        _loading = false;
      });
      // Scroll to bottom after loading
      _scrollToBottom();
    } catch (e) {
      debugPrint('❌ Error loading messages: $e');
      setState(() {
        _loading = false;
      });
    }

    // 2) Subscribe to realtime inserts for this ride
    debugPrint('🔔 Subscribing to realtime messages for ride ${widget.rideId}');
    _channel = SupabaseService.subscribeMessages(widget.rideId, (m) {
      debugPrint('📩 Received new message: $m');
      setState(() {
        messages.add(m);
      });
      _scrollToBottom();
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollController.dispose();
    SupabaseService.unsubscribeChannel(_channel);
    super.dispose();
  }

  Future<void> _sendMessage(String txt) async {
    if (txt.trim().isEmpty) return;
    try {
      debugPrint('📤 Sending message: ride=${widget.rideId}, from=${widget.myUserId}, to=${widget.peerUserId}');
      await SupabaseService.sendMessage(
        rideId: widget.rideId,
        fromUserId: widget.myUserId,
        toUserId: widget.peerUserId,
        content: txt.trim(),
      );
      
      // Send notification to peer about new message
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser != null) {
        String userName = 'Driver';
        try {
          final profile = await Supabase.instance.client
              .from('profiles')
              .select('full_name')
              .eq('id', widget.myUserId)
              .maybeSingle();
          if (profile != null) {
            userName = profile['full_name']?.toString() ?? 'Driver';
          }
        } catch (_) {}

        NotificationService().createNotification(
          userId: widget.peerUserId,
          title: '💬 Message from $userName',
          body: txt.length > 50 ? '${txt.substring(0, 47)}...' : txt,
          type: 'chat',
          data: {
            'ride_id': widget.rideId,
            'from_user': widget.myUserId,
          },
        );
      }
      
      _ctrl.clear();
      debugPrint('✅ Message sent successfully');
      // Message will arrive via realtime subscription and be added to `messages`
    } catch (e) {
      debugPrint('❌ Error sending message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send message: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const campusGreen = Color(0xFF00BFA6);

    return Scaffold(
      appBar: AppBar(
        title: Text('Chat with ${widget.peerName}'),
        backgroundColor: campusGreen,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : messages.isEmpty
                    ? const Center(
                        child: Text(
                          'No messages yet.\nStart the conversation!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        itemCount: messages.length,
                        itemBuilder: (context, idx) {
                          final msg = messages[idx];
                          final fromUserId = msg['from_user']?.toString() ?? '';
                          final content = msg['message']?.toString() ?? '';
                          final isMine = fromUserId == widget.myUserId;
                          final timestamp = msg['created_at']?.toString() ?? '';

                          // Parse timestamp for display
                          String timeStr = '';
                          if (timestamp.isNotEmpty) {
                            try {
                              final dt = DateTime.parse(timestamp);
                              timeStr =
                                  '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
                            } catch (_) {
                              timeStr = '';
                            }
                          }

                          return Align(
                            alignment: isMine
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: Container(
                              margin: const EdgeInsets.symmetric(
                                  vertical: 8, horizontal: 12),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: isMine
                                    ? campusGreen
                                    : Colors.grey.shade300,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Column(
                                crossAxisAlignment: isMine
                                    ? CrossAxisAlignment.end
                                    : CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    content,
                                    style: TextStyle(
                                      color: isMine
                                          ? Colors.white
                                          : Colors.black87,
                                      fontSize: 15,
                                    ),
                                  ),
                                  if (timeStr.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      timeStr,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: isMine
                                            ? Colors.white70
                                            : Colors.black54,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (t) => _sendMessage(t),
                      maxLines: null,
                      minLines: 1,
                      decoration: InputDecoration(
                        hintText: 'Type a message',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: campusGreen,
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      onPressed: () => _sendMessage(_ctrl.text),
                      icon: const Icon(Icons.send, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
