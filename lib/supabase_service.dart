// lib/supabase_service.dart
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:realtime_client/realtime_client.dart' show RealtimeChannel, PostgresChangeEvent, PostgresChangeFilter, PostgresChangeFilterType;

class SupabaseService {
  static final _supabase = Supabase.instance.client;

  static Map<String, dynamic> _normalizeMessageRow(Map<String, dynamic> row) {
    final fromUser = row.containsKey('from_user') ? row['from_user'] : (row.containsKey('sender_id') ? row['sender_id'] : (row.containsKey('sender') ? row['sender'] : (row.containsKey('user_id') ? row['user_id'] : null)));
    final toUser = row.containsKey('to_user') ? row['to_user'] : (row.containsKey('receiver_id') ? row['receiver_id'] : (row.containsKey('receiver') ? row['receiver'] : (row.containsKey('peer_id') ? row['peer_id'] : null)));
    final message = row.containsKey('message') ? row['message'] : (row.containsKey('content') ? row['content'] : (row.containsKey('text') ? row['text'] : (row.containsKey('message_text') ? row['message_text'] : null)));
    final createdAt = row.containsKey('created_at') ? row['created_at'] : (row.containsKey('createdAt') ? row['createdAt'] : null);

    final normalized = <String, dynamic>{
      'ride_id': row['ride_id'] ?? row['rideId'],
      'from_user': fromUser,
      'to_user': toUser,
      'message': message,
      'created_at': createdAt,
    };
    return normalized;
  }

  /// Subscribe to messages for a particular ride.
  /// Returns the RealtimeChannel. Call `Supabase.instance.client.removeChannel(channel)` when you want to stop listening.
  static RealtimeChannel subscribeMessages(
    String rideId,
    void Function(Map<String, dynamic> message) onMessage,
  ) {
    final channel = _supabase.channel('chat:$rideId');

    channel
        .onPostgresChanges(
          // we only care about new rows (INSERT)
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          // Filter so we only get rows where ride_id == provided rideId
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'ride_id',
            value: rideId,
          ),
          callback: (payload) {
            try {
              final record = Map<String, dynamic>.from(payload.newRecord);
              onMessage(_normalizeMessageRow(record));
            } catch (e) {
              // ignore malformed payloads
            }
          },
        )
        .subscribe();

    return channel;
  }

  /// Insert a message into the messages table.
  /// Relying on DB insert + Postgres-change ensures other clients subscribed to the messages table will receive it.
  static Future<void> sendMessage({
    required String rideId,
    required String fromUserId,
    required String toUserId,
    required String content,
  }) async {
    final now = DateTime.now().toIso8601String();
    try {
      await _supabase.from('messages').insert({
        'ride_id': rideId,
        'from_user': fromUserId,
        'to_user': toUserId,
        'message': content,
        'created_at': now,
      }).select();
    } on PostgrestException catch (_) {
      // Fallback to legacy column names
      await _supabase.from('messages').insert({
        'ride_id': rideId,
        'sender_id': fromUserId,
        'receiver_id': toUserId,
        'content': content,
        'createdAt': now,
      }).select();
    }
  }

  /// Fetch historical messages for the ride (ordered by created_at ascending).
  static Future<List<Map<String, dynamic>>> fetchMessages(String rideId) async {
    final data = await _supabase
        .from('messages')
        .select()
        .eq('ride_id', rideId)
        .order('created_at', ascending: true);

    final list = List<Map<String, dynamic>>.from(data as List);
    return list.map(_normalizeMessageRow).toList();
  }

  /// Unsubscribe and remove a channel created by subscribeMessages().
  static Future<void> unsubscribeChannel(RealtimeChannel? channel) async {
    if (channel == null) return;
    try {
      await _supabase.removeChannel(channel);
    } catch (e) {
      // best-effort: ignore errors during cleanup
    }
  }
}
