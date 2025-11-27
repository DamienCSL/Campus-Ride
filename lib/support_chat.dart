// support_chat.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

class SupportChatPage extends StatefulWidget {
  final String rideId;
  final String peerUserId; // the other user's id (driver or rider)
  const SupportChatPage({Key? key, required this.rideId, required this.peerUserId}) : super(key: key);

  @override
  State<SupportChatPage> createState() => _SupportChatPageState();
}

class _SupportChatPageState extends State<SupportChatPage> {
  final supabase = Supabase.instance.client;
  final TextEditingController ctrl = TextEditingController();
  List<Map<String,dynamic>> messages = [];
  RealtimeChannel? _sub;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _sub = SupabaseService.subscribeMessages(widget.rideId, (m) {
      setState(() => messages.add(m));
    });
  }

  Future<void> _loadMessages() async {
    final res = await supabase.from('messages').select().eq('ride_id', widget.rideId).order('created_at', ascending: true);
    setState(() {
      messages = List<Map<String,dynamic>>.from(res as List<dynamic>);
    });
  }

  @override
  void dispose() {
    if (_sub != null) supabase.removeChannel(_sub!);
    ctrl.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final txt = ctrl.text.trim();
    if (txt.isEmpty) return;
    await SupabaseService.sendMessage(rideId: widget.rideId, toUserId: widget.peerUserId, message: txt);
    ctrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final uid = supabase.auth.currentUser!.id;
    return Scaffold(
      appBar: AppBar(title: const Text('Chat')),
      body: Column(
        children: [
          Expanded(child: ListView(
            padding: const EdgeInsets.all(12),
            children: messages.map((m) {
              final isMe = m['from_user'] == uid;
              return Align(
                alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 6),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: isMe ? Colors.green[100] : Colors.grey[200], borderRadius: BorderRadius.circular(8)),
                  child: Text(m['message']),
                ),
              );
            }).toList(),
          )),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(child: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'Type message'))),
                IconButton(icon: const Icon(Icons.send), onPressed: _send)
              ],
            ),
          )
        ],
      ),
    );
  }
}
