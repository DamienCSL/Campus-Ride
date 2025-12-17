// lib/admin_support_chat.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'admin_chat_conversation.dart';

class AdminSupportChatPage extends StatefulWidget {
  const AdminSupportChatPage({Key? key}) : super(key: key);

  @override
  State<AdminSupportChatPage> createState() => _AdminSupportChatPageState();
}

class _AdminSupportChatPageState extends State<AdminSupportChatPage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _chatSessions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadChatSessions();
  }

  Future<void> _loadChatSessions() async {
    setState(() => _isLoading = true);
    
    try {
      // Get all support chat sessions (any status), newest first
      final chatsData = await supabase
          .from('support_chats')
          .select('*, profiles!support_chats_user_id_fkey(full_name, phone)')
          .order('updated_at', ascending: false);

      if (mounted) {
        setState(() {
          _chatSessions = List<Map<String, dynamic>>.from(chatsData as List);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading chat sessions: $e');
      setState(() => _isLoading = false);
    }
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return '';
    try {
      final dt = DateTime.parse(timestamp.toString());
      final now = DateTime.now();
      final diff = now.difference(dt);
      
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (e) {
      return '';
    }
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'open':
        return Colors.orange;
      case 'in_progress':
        return Colors.blue;
      case 'resolved':
        return Colors.green;
      case 'closed':
        return Colors.grey;
      default:
        return Colors.orange;
    }
  }

  String _getStatusLabel(String? status) {
    switch (status) {
      case 'open':
        return 'OPEN';
      case 'in_progress':
        return 'IN PROGRESS';
      case 'resolved':
        return 'RESOLVED';
      case 'closed':
        return 'CLOSED';
      default:
        return 'OPEN';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Support Chat'),
        backgroundColor: Colors.teal,
        actions: [
          IconButton(
            icon: const Icon(Icons.archive),
            tooltip: 'View Archived Chats',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ArchivedChatsPage(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadChatSessions,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _chatSessions.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No support chats yet',
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadChatSessions,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _chatSessions.length,
                    itemBuilder: (context, index) {
                      if (index == 0) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey[100],
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey[300]!),
                          ),
                          child: Text(
                            'Chats: ${_chatSessions.length}',
                            style: TextStyle(fontSize: 13, color: Colors.grey[800]),
                          ),
                        );
                      }

                      final chatIndex = index - 1;
                      final chat = _chatSessions[chatIndex];
                      final chatId = chat['id']?.toString() ?? '';
                      final profile = chat['profiles'] as Map<String, dynamic>?;
                      final userName = profile?['full_name'] ?? 'Unknown User';
                      final status = chat['status']?.toString() ?? 'open';
                      final hasUnread = chat['has_unread_admin'] == true;
                      
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: hasUnread ? 4 : 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: hasUnread
                              ? const BorderSide(color: Colors.teal, width: 2)
                              : BorderSide.none,
                        ),
                        child: InkWell(
                          onTap: () {
                            // Navigate to chat conversation
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AdminChatConversationPage(
                                  chatId: chatId,
                                  userProfile: profile ?? {},
                                ),
                              ),
                            ).then((_) => _loadChatSessions()); // Refresh when returning
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Stack(
                                      children: [
                                        CircleAvatar(
                                          backgroundColor: Colors.grey[300],
                                          child: const Icon(Icons.person),
                                        ),
                                        if (hasUnread)
                                          Positioned(
                                            right: 0,
                                            top: 0,
                                            child: Container(
                                              width: 12,
                                              height: 12,
                                              decoration: const BoxDecoration(
                                                color: Colors.red,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            userName,
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: hasUnread
                                                  ? FontWeight.bold
                                                  : FontWeight.w600,
                                            ),
                                          ),
                                          if (chat['subject'] != null)
                                            Text(
                                              chat['subject'],
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _getStatusColor(status).withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            _getStatusLabel(status),
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: _getStatusColor(status),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _formatTimestamp(chat['updated_at'] ?? chat['created_at']),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[500],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                if (chat['last_message'] != null) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    chat['last_message'],
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[700],
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(Icons.phone, size: 14, color: Colors.grey[600]),
                                    const SizedBox(width: 6),
                                    Text(
                                      profile?['phone'] ?? 'No phone',
                                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
// Archived Chats Page
class ArchivedChatsPage extends StatefulWidget {
  const ArchivedChatsPage({Key? key}) : super(key: key);

  @override
  State<ArchivedChatsPage> createState() => _ArchivedChatsPageState();
}

class _ArchivedChatsPageState extends State<ArchivedChatsPage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _archivedChats = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadArchivedChats();
  }

  Future<void> _loadArchivedChats() async {
    setState(() => _isLoading = true);
    
    try {
      // Get all closed support chat sessions
      final chatsData = await supabase
          .from('support_chats')
          .select('*, profiles!support_chats_user_id_fkey(full_name, phone)')
          .eq('status', 'closed')
          .order('updated_at', ascending: false);

      if (mounted) {
        setState(() {
          _archivedChats = List<Map<String, dynamic>>.from(chatsData as List);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading archived chats: $e');
      setState(() => _isLoading = false);
    }
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return '';
    try {
      final dt = DateTime.parse(timestamp.toString());
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Archived Chats'),
        backgroundColor: Colors.teal,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _archivedChats.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.archive_outlined, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No archived chats yet',
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadArchivedChats,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _archivedChats.length,
                    itemBuilder: (context, index) {
                      final chat = _archivedChats[index];
                      final profile = chat['profiles'] as Map<String, dynamic>?;
                      final userName = profile?['full_name'] ?? 'Unknown User';
                      
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: InkWell(
                          onTap: () {
                            // Navigate to chat conversation (read-only)
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => AdminChatConversationPage(
                                  chatId: chat['id']?.toString() ?? '',
                                  userProfile: profile ?? {},
                                ),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: Colors.grey[300],
                                      child: const Icon(Icons.person),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            userName,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          if (chat['subject'] != null)
                                            Text(
                                              chat['subject'],
                                              style: TextStyle(
                                                fontSize: 13,
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: const Text(
                                            'ARCHIVED',
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.grey,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _formatTimestamp(chat['updated_at']),
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[500],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                if (chat['last_message'] != null) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    chat['last_message'],
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[700],
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Icon(Icons.phone, size: 14, color: Colors.grey[600]),
                                    const SizedBox(width: 6),
                                    Text(
                                      profile?['phone'] ?? 'No phone',
                                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}