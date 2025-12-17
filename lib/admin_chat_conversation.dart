// lib/admin_chat_conversation.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'notification_service.dart';

class AdminChatConversationPage extends StatefulWidget {
  final String chatId;
  final Map<String, dynamic> userProfile;

  const AdminChatConversationPage({
    Key? key,
    required this.chatId,
    required this.userProfile,
  }) : super(key: key);

  @override
  State<AdminChatConversationPage> createState() =>
      _AdminChatConversationPageState();
}

class _AdminChatConversationPageState extends State<AdminChatConversationPage> {
  final supabase = Supabase.instance.client;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  RealtimeChannel? _subscription;
  String _chatStatus = 'open';

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _subscribeToMessages();
    _markAsRead();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _subscription?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    try {
      // Load chat status first
      final chatData = await supabase
          .from('support_chats')
          .select('status')
          .eq('id', widget.chatId)
          .single();
      
      if (mounted) {
        setState(() {
          _chatStatus = chatData['status'] ?? 'open';
        });
      }

      final messagesData = await supabase
          .from('support_messages')
          .select()
          .eq('chat_id', widget.chatId)
          .order('created_at', ascending: true);

      if (mounted) {
        setState(() {
          _messages = List<Map<String, dynamic>>.from(messagesData as List);
          _isLoading = false;
        });

        // Scroll to bottom
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading messages: $e');
      setState(() => _isLoading = false);
    }
  }

  void _subscribeToMessages() {
    // Listen for new messages for this chat
    _subscription = supabase
        .channel('public:support_messages')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'support_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'chat_id',
            value: widget.chatId,
          ),
          callback: (payload) {
            if (mounted) {
              setState(() {
                _messages.add(payload.newRecord);
              });
              // Scroll to bottom
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
          },
        )
        .subscribe();

    // Also listen for chat status changes
    supabase
        .channel('public:support_chats')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'support_chats',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.chatId,
          ),
          callback: (payload) {
            if (mounted) {
              setState(() {
                _chatStatus = payload.newRecord['status'] ?? 'open';
              });
            }
          },
        )
        .subscribe();
  }

  Future<void> _markAsRead() async {
    try {
      await supabase.from('support_chats').update({
        'has_unread_admin': false,
      }).eq('id', widget.chatId);
    } catch (e) {
      debugPrint('Error marking as read: $e');
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty) return;

    final messageText = _messageController.text.trim();
    _messageController.clear();

    try {
      final adminId = supabase.auth.currentUser!.id;
      final userId = widget.userProfile['id']?.toString();

      await supabase.from('support_messages').insert({
        'chat_id': widget.chatId,
        'sender_id': adminId,
        'message': messageText,
        'is_admin': true,
      });

      // Update chat's updated_at and last_message
      await supabase.from('support_chats').update({
        'updated_at': DateTime.now().toIso8601String(),
        'last_message': messageText,
        'status': 'in_progress',
      }).eq('id', widget.chatId);

      // Send notification to user
      if (userId != null) {
        NotificationService().createNotification(
          userId: userId,
          title: '💬 Admin Replied',
          body: messageText.length > 50 ? '${messageText.substring(0, 47)}...' : messageText,
          type: 'support',
          data: {
            'chat_id': widget.chatId,
          },
        );
      }
    } catch (e) {
      debugPrint('Error sending message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send message: $e')),
        );
      }
    }
  }

  Future<void> _updateChatStatus(String status) async {
    try {
      await supabase.from('support_chats').update({
        'status': status,
      }).eq('id', widget.chatId);

      if (mounted) {
        setState(() => _chatStatus = status);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Chat marked as $status')),
        );
      }
    } catch (e) {
      debugPrint('Error updating chat status: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final userName = widget.userProfile['full_name'] ?? 'User';
    final userPhone = widget.userProfile['phone'] ?? '';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(userName),
            if (userPhone.isNotEmpty)
              Text(
                userPhone,
                style: const TextStyle(fontSize: 12),
              ),
          ],
        ),
        backgroundColor: const Color(0xFF00BFA6),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload chat',
            onPressed: _loadMessages,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              _updateChatStatus(value);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'in_progress',
                child: Text('Mark In Progress'),
              ),
              const PopupMenuItem(
                value: 'resolved',
                child: Text('Mark Resolved'),
              ),
              const PopupMenuItem(
                value: 'closed',
                child: Text('Close Chat'),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  color: Colors.grey[100],
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Text(
                    'Chat: ${widget.chatId}  •  Status: $_chatStatus  •  Messages: ${_messages.length}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Messages list
                Expanded(
                  child: _messages.isEmpty
                      ? const Center(
                          child: Text(
                            'No messages yet',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: _chatStatus == 'closed' 
                              ? _messages.length + 1
                              : _messages.length,
                          itemBuilder: (context, index) {
                            // Show closed message at the end if chat is closed
                            if (_chatStatus == 'closed' && index == _messages.length) {
                              return Center(
                                child: Container(
                                  margin: const EdgeInsets.symmetric(vertical: 20),
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.grey[200],
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    children: [
                                      const Icon(
                                        Icons.check_circle,
                                        color: Colors.green,
                                        size: 32,
                                      ),
                                      const SizedBox(height: 8),
                                      const Text(
                                        'Admin has marked this chat as done',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black87,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }

                            final message = _messages[index];
                            final isAdmin = message['is_admin'] == true;
                            final messageText = message['message'] ?? '';
                            final timestamp = message['created_at'];

                            return _buildMessageBubble(
                              messageText,
                              isAdmin,
                              timestamp,
                            );
                          },
                        ),
                ),

                // Input area (only show if chat is not closed)
                if (_chatStatus != 'closed')
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 5,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      child: Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _messageController,
                              decoration: InputDecoration(
                                hintText: 'Type your reply...',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(24),
                                  borderSide: BorderSide.none,
                                ),
                                filled: true,
                                fillColor: Colors.grey[100],
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 10,
                                ),
                              ),
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _sendMessage(),
                            ),
                          ),
                          const SizedBox(width: 8),
                          CircleAvatar(
                            backgroundColor: const Color(0xFF00BFA6),
                            child: IconButton(
                              icon: const Icon(Icons.send, color: Colors.white),
                              onPressed: _sendMessage,
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

  Widget _buildMessageBubble(String message, bool isAdmin, dynamic timestamp) {
    return Align(
      alignment: isAdmin ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        decoration: BoxDecoration(
          color: isAdmin ? const Color(0xFF00BFA6) : Colors.grey[200],
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isAdmin)
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text(
                  'User',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.black54,
                  ),
                ),
              ),
            Text(
              message,
              style: TextStyle(
                color: isAdmin ? Colors.white : Colors.black87,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatTime(timestamp),
              style: TextStyle(
                fontSize: 10,
                color: isAdmin ? Colors.white70 : Colors.black45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return '';
    try {
      final dt = DateTime.parse(timestamp.toString());
      final now = DateTime.now();

      if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
        return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } else {
        return '${dt.day}/${dt.month} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      }
    } catch (e) {
      return '';
    }
  }
}
