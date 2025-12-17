// lib/user_support_chat.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'notification_service.dart';

class UserSupportChatPage extends StatefulWidget {
  const UserSupportChatPage({Key? key}) : super(key: key);

  @override
  State<UserSupportChatPage> createState() => _UserSupportChatPageState();
}

class _UserSupportChatPageState extends State<UserSupportChatPage> {
  final supabase = Supabase.instance.client;
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  
  String? _chatId;
  List<Map<String, dynamic>> _messages = [];
  bool _isLoading = true;
  RealtimeChannel? _subscription;
  RealtimeChannel? _statusSubscription;
  String _chatStatus = 'open';

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _resetSubscriptions();
    super.dispose();
  }

  void _resetSubscriptions() {
    _subscription?.unsubscribe();
    _subscription = null;
    _statusSubscription?.unsubscribe();
    _statusSubscription = null;
  }

  Future<void> _initializeChat() async {
    try {
      final userId = supabase.auth.currentUser!.id;
      
      // 1) Prefer an open/in_progress chat if it exists
      final existingChats = await supabase
          .from('support_chats')
          .select()
          .eq('user_id', userId)
          .inFilter('status', ['open', 'in_progress'])
          .order('created_at', ascending: false)
          .limit(1);

      if (existingChats.isNotEmpty) {
        _chatId = existingChats[0]['id'];
      } else {
        // 2) If no active chat, fall back to the most recent chat (any status)
        final latestAny = await supabase
            .from('support_chats')
            .select()
            .eq('user_id', userId)
            .order('created_at', ascending: false)
            .limit(1);

        if (latestAny.isNotEmpty) {
          _chatId = latestAny[0]['id'];
        } else {
          // 3) No chats at all — create a new one
          final newChat = await supabase
              .from('support_chats')
              .insert({
                'user_id': userId,
                'subject': 'Support Request',
                'status': 'open',
              })
              .select()
              .single();
          _chatId = newChat['id'];
        }
      }

      // Load initial chat status
      await _loadChatStatus();

      // Load messages and status
      await _loadMessages();
      
      // Subscribe to new messages
      _subscribeToMessages();
      
      // Subscribe to chat status changes
      _subscribeToChatStatus();

      setState(() => _isLoading = false);
      
      // Scroll to bottom
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    } catch (e) {
      debugPrint('Error initializing chat: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading chat: $e')),
        );
      }
    }
  }

  Future<void> _startNewChat() async {
    final userId = supabase.auth.currentUser!.id;
    try {
      setState(() {
        _isLoading = true;
        _messages = [];
      });

      _resetSubscriptions();

      final newChat = await supabase
          .from('support_chats')
          .insert({
            'user_id': userId,
            'subject': 'Support Request',
            'status': 'open',
          })
          .select()
          .single();

      _chatId = newChat['id'];
      _chatStatus = (newChat['status'] as String?) ?? 'open';

      // Fresh subscriptions for new chat
      _subscribeToMessages();
      _subscribeToChatStatus();

      await _loadMessages();

      setState(() => _isLoading = false);

      // Scroll to bottom after a frame
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
      });
    } catch (e) {
      debugPrint('Error starting new chat: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start new chat: $e')),
        );
      }
    }
  }

  Future<void> _loadChatStatus() async {
    if (_chatId == null) return;
    try {
      final chat = await supabase
          .from('support_chats')
          .select('status')
          .eq('id', _chatId!)
          .single();
      if (mounted) {
        setState(() {
          _chatStatus = (chat['status'] as String?) ?? 'open';
        });
      }
    } catch (e) {
      debugPrint('Error loading chat status: $e');
    }
  }

  Future<void> _loadMessages() async {
    if (_chatId == null) return;
    
    try {
      final messagesData = await supabase
          .from('support_messages')
          .select()
          .eq('chat_id', _chatId!)
          .order('created_at', ascending: true);

      setState(() {
        _messages = List<Map<String, dynamic>>.from(messagesData as List);
      });
    } catch (e) {
      debugPrint('Error loading messages: $e');
    }
  }

  void _subscribeToMessages() {
    if (_chatId == null) return;
    _subscription?.unsubscribe();

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
            value: _chatId,
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
  }

  void _subscribeToChatStatus() {
    if (_chatId == null) return;
    _statusSubscription?.unsubscribe();
    
    // Listen for chat status changes
    _statusSubscription = supabase
        .channel('public:support_chats')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'support_chats',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: _chatId,
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

  Future<void> _sendMessage() async {
    if (_messageController.text.trim().isEmpty || _chatId == null) return;

    final messageText = _messageController.text.trim();
    _messageController.clear();

    try {
      final userId = supabase.auth.currentUser!.id;
      
      await supabase.from('support_messages').insert({
        'chat_id': _chatId,
        'sender_id': userId,
        'message': messageText,
        'is_admin': false,
      });

      // Optimistically add the message locally so the user sees it immediately
      setState(() {
        _messages.add({
          'chat_id': _chatId,
          'sender_id': userId,
          'message': messageText,
          'is_admin': false,
          'created_at': DateTime.now().toIso8601String(),
        });
      });

      // Keep the list scrolled to bottom
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });

      // Update chat's updated_at and last_message, notify admin
      await supabase.from('support_chats').update({
        'updated_at': DateTime.now().toIso8601String(),
        'last_message': messageText,
        'has_unread_admin': true,
      }).eq('id', _chatId!);

      // Send notification to admin
      NotificationService().createNotification(
        userId: 'admin', // Notify admin role
        title: '💬 New User Message',
        body: messageText.length > 50 ? '${messageText.substring(0, 47)}...' : messageText,
        type: 'support',
        data: {
          'chat_id': _chatId,
          'user_id': userId,
        },
      );

    } catch (e) {
      debugPrint('Error sending message: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send message: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Support Chat'),
        backgroundColor: const Color(0xFF00BFA6),
        foregroundColor: Colors.white,
            actions: [
              IconButton(
                icon: const Icon(Icons.add_comment),
                tooltip: 'Start new chat',
                onPressed: _startNewChat,
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () async {
                  await _loadChatStatus();
                  await _loadMessages();
                },
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
                    'Chat: ${_chatId ?? '-'}  •  Status: ${_chatStatus}  •  Messages: ${_messages.length}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Messages list
                Expanded(
                  child: _messages.isEmpty
                      ? const Center(
                          child: Text(
                            'Send a message to start chatting with support',
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
                                  child: const Column(
                                    children: [
                                      Icon(
                                        Icons.check_circle,
                                        color: Colors.green,
                                        size: 32,
                                      ),
                                      SizedBox(height: 8),
                                      Text(
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
                                hintText: 'Type your message...',
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
      alignment: isAdmin ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.7,
        ),
        decoration: BoxDecoration(
          color: isAdmin ? Colors.grey[200] : const Color(0xFF00BFA6),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isAdmin)
              const Padding(
                padding: EdgeInsets.only(bottom: 4),
                child: Text(
                  'Support Team',
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
                color: isAdmin ? Colors.black87 : Colors.white,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _formatTime(timestamp),
              style: TextStyle(
                fontSize: 10,
                color: isAdmin ? Colors.black45 : Colors.white70,
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
