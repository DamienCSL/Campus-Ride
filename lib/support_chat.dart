// lib/support_chat.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:realtime_client/realtime_client.dart' show RealtimeChannel;
import 'supabase_service.dart';

class SupportChatPage extends StatefulWidget {
  final String rideId;
  final String peerUserId; // the other user's id
  final String myUserId;

  const SupportChatPage({
    Key? key,
    required this.rideId,
    required this.peerUserId,
    required this.myUserId,
  }) : super(key: key);

  @override
  State<SupportChatPage> createState() => _SupportChatPageState();
}

class _SupportChatPageState extends State<SupportChatPage> {
  RealtimeChannel? _channel;
  final List<Map<String, dynamic>> messages = [];
  final TextEditingController _ctrl = TextEditingController();
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _initChat();
  }

  Future<void> _initChat() async {
    // 1) load history
    try {
      final hist = await SupabaseService.fetchMessages(widget.rideId);
      setState(() {
        messages.addAll(hist);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
      });
    }

    // 2) subscribe to realtime inserts for this ride
    _channel = SupabaseService.subscribeMessages(widget.rideId, (m) {
      // payload is a map representing the inserted row
      setState(() {
        messages.add(m);
      });
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    SupabaseService.unsubscribeChannel(_channel);
    super.dispose();
  }

  Future<void> _sendMessage(String txt) async {
    if (txt.trim().isEmpty) return;
    try {
      await SupabaseService.sendMessage(
        rideId: widget.rideId,
        fromUserId: widget.myUserId,
        toUserId: widget.peerUserId,
        content: txt.trim(),
      );
      _ctrl.clear();
      // message will arrive via realtime subscription and be added to `messages`
    } catch (e) {
      // show error if needed
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send message')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Support Chat'),
      ),
      body: Column(
        children: [
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: messages.length,
                    itemBuilder: (context, idx) {
                      final msg = messages[idx];
                      final from = msg['from_user_id']?.toString() ?? '';
                      final content = msg['content']?.toString() ?? '';
                      final isMine = from == widget.myUserId;
                      return Align(
                        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isMine ? Colors.blueAccent : Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            content,
                            style: TextStyle(color: isMine ? Colors.white : Colors.black87),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (t) => _sendMessage(t),
                      decoration: const InputDecoration(
                        hintText: 'Type a message',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => _sendMessage(_ctrl.text),
                    child: const Text('Send'),
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
