import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  static final SupabaseClient supabase = Supabase.instance.client;

  // ----------------------------
  // LISTEN FOR NEW RIDE REQUESTS
  // ----------------------------
  static RealtimeChannel listenForNewRideRequests({
    required void Function(Map payload) onRequest,
  }) {
    final channel = supabase.channel('ride_requests_channel');

    channel.on(
      'postgres_changes',
      ChannelFilter(
        event: 'INSERT',
        schema: 'public',
        table: 'ride_requests',
      ),
          (payload, [ref]) {
        onRequest(payload['new']); // old API style
      },
    );

    channel.subscribe();
    return channel;
  }

  // ----------------------------
  // LISTEN FOR RIDE UPDATES
  // ----------------------------
  static RealtimeChannel listenForRideUpdates({
    required String rideId,
    required void Function(Map payload) onUpdate,
  }) {
    final channel = supabase.channel('ride_updates_$rideId');

    channel.on(
      'postgres_changes',
      ChannelFilter(
        event: 'UPDATE',
        schema: 'public',
        table: 'ride_requests',
        filter: 'id=eq.$rideId', // old API format
      ),
          (payload, [ref]) {
        onUpdate(payload['new']);
      },
    );

    channel.subscribe();
    return channel;
  }

  // ----------------------------
  // LISTEN FOR CHAT MESSAGES
  // ----------------------------
  static RealtimeChannel listenForMessages({
    required String rideId,
    required void Function(Map msg) onMessage,
  }) {
    final channel = supabase.channel('messages_$rideId');

    channel.on(
      'postgres_changes',
      ChannelFilter(
        event: 'INSERT',
        schema: 'public',
        table: 'messages',
        filter: 'ride_id=eq.$rideId',
      ),
          (payload, [ref]) {
        onMessage(payload['new']);
      },
    );

    channel.subscribe();
    return channel;
  }
}
