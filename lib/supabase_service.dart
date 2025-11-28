// lib/supabase_service.dart
import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:realtime_client/realtime_client.dart' show RealtimeChannel, PostgresChangeEvent, PostgresChangeFilter, PostgresChangeFilterType;

class SupabaseService {
  static final _supabase = Supabase.instance.client;

  /// Subscribe to messages for a particular ride.
  /// Returns the RealtimeChannel. Call `Supabase.instance.client.removeChannel(channel)` when you want to stop listening.
  static RealtimeChannel subscribeMessages(
    String rideId,
    void Function(Map<String, dynamic> message) onMessage,
  ) {
    final topic = 'public:messages:ride_id=eq.$rideId'; // descriptive topic (not required but OK)
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
            if (payload.newRecord != null) {
              try {
                final record = Map<String, dynamic>.from(payload.newRecord!);
                onMessage(record);
              } catch (e) {
                // ignore malformed payloads
              }
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

    final result = await _supabase.from('messages').insert({
      'ride_id': rideId,
      'from_user_id': fromUserId,
      'to_user_id': toUserId,
      'content': content,
      'created_at': now,
    }).select(); // select returns the inserted rows (optional)

    if (result == null) {
      throw Exception('Failed to insert message');
    }
  }

  /// Fetch historical messages for the ride (ordered by created_at ascending).
  static Future<List<Map<String, dynamic>>> fetchMessages(String rideId) async {
    final data = await _supabase
        .from('messages')
        .select()
        .eq('ride_id', rideId)
        .order('created_at', ascending: true);

    if (data == null) return [];

    // data is usually a List<dynamic> of maps
    return List<Map<String, dynamic>>.from(data as List);
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
