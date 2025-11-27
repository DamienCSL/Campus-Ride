import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login.dart';
import 'book_trip.dart'; // optional if you want to show map/route when tapping

class DriverDashboard extends StatefulWidget {
  const DriverDashboard({Key? key}) : super(key: key);

  @override
  State<DriverDashboard> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard> {
  final SupabaseClient supabase = Supabase.instance.client;
  RealtimeChannel? _channel;
  List<Map<String, dynamic>> _openRequests = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    _unsubscribe();
    super.dispose();
  }

  Future<void> _init() async {
    await _loadOpenRequests();
    _subscribeToOpenRequests();
  }

  Future<void> _loadOpenRequests() async {
    setState(() => _loading = true);
    try {
      final res = await supabase
          .from('ride_requests')
          .select()
          .eq('status', 'open')
          .order('requested_at', ascending: false);
      _openRequests = List<Map<String, dynamic>>.from(res);
    } catch (e) {
      // ignore or handle
    } finally {
      setState(() => _loading = false);
    }
  }

  void _subscribeToOpenRequests() {
    // Create a channel name unique to this purpose
    _channel = supabase.channel('public:ride_requests');

    // Listen for new inserts to ride_requests table
    _channel!.onPostgresChanges(
      event: PostgresChangeEvent.insert,
      schema: 'public',
      table: 'ride_requests',
      callback: (payload) {
        final newRow = Map<String, dynamic>.from(payload.newRecord);
        if (newRow['status'] == 'open') {
          setState(() {
            _openRequests.insert(0, newRow);
          });
        }
      },
    );

    // Listen for updates — to remove requests that changed status or were assigned
    _channel!.onPostgresChanges(
      event: PostgresChangeEvent.update,
      schema: 'public',
      table: 'ride_requests',
      callback: (payload) {
        final updated = Map<String, dynamic>.from(payload.newRecord);
        final id = updated['id'];
        setState(() {
          // remove any matched existing request and re-add if still open
          _openRequests.removeWhere((r) => r['id'] == id);
          if (updated['status'] == 'open') {
            _openRequests.insert(0, updated);
          }
        });
      },
    );

    _channel!.subscribe();
  }

  void _unsubscribe() {
    if (_channel != null) {
      supabase.removeChannel(_channel!);
      _channel = null;
    }
  }

  Future<void> _acceptRequest(Map<String, dynamic> request) async {
    // atomic-ish update: only set to assigned if still open
    final user = supabase.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Not signed in')));
      return;
    }

    final id = request['id'];

    try {
      final result = await supabase
          .from('ride_requests')
          .update({
        'status': 'assigned',
        'assigned_driver': user.id,
        'assigned_at': DateTime.now().toIso8601String(),
      })
          .eq('id', id)
          .eq('status', 'open')
          .select()
          .maybeSingle();

      if (result == null) {
        // failed to assign (maybe assigned by another driver)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to accept — already assigned')));
        // refresh list quickly
        await _loadOpenRequests();
        return;
      }

      // success — remove from open requests list locally
      setState(() {
        _openRequests.removeWhere((r) => r['id'] == id);
      });

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ride accepted')));
      // optionally navigate to a driver trip page with details
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Widget _buildRequestCard(Map<String, dynamic> r) {
    final pickup = r['pickup_address'] ?? '${r['pickup_lat']}, ${r['pickup_lng']}';
    final dest = r['destination_address'] ?? '${r['destination_lat']}, ${r['destination_lng']}';
    final fare = r['estimated_fare'] != null ? 'RM ${r['estimated_fare']}' : '—';
    final dist = r['distance_km'] != null ? '${(r['distance_km'] as num).toString()} km' : '—';
    final requestedAt = r['requested_at'] != null ? r['requested_at'] : '';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(pickup, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.location_on_outlined, size: 16, color: Colors.grey),
                const SizedBox(width: 6),
                Expanded(child: Text(dest)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Text('Fare: $fare'),
                const SizedBox(width: 16),
                Text('Distance: $dist'),
                const Spacer(),
                Text(requestedAt.toString(), style: const TextStyle(color: Colors.grey, fontSize: 12)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ElevatedButton(
                  onPressed: () => _acceptRequest(r),
                  child: const Text('Accept'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () {
                    // optional: preview on map or message rider
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => BookTripPageMock(requestData: r)),
                    );
                  },
                  child: const Text('Preview'),
                )
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const campusGreen = Color(0xFF00BFA6);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Dashboard'),
        backgroundColor: campusGreen,
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () async {
                await _loadOpenRequests();
              }),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await supabase.auth.signOut();
              Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const Login()));
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _openRequests.isEmpty
          ? const Center(child: Text('No open requests'))
          : ListView.builder(
        padding: const EdgeInsets.only(top: 12, bottom: 24),
        itemCount: _openRequests.length,
        itemBuilder: (_, i) {
          final r = _openRequests[i];
          return _buildRequestCard(r);
        },
      ),
    );
  }
}

/// Mock page to show request details (replace with your driver-trip / navigation page)
class BookTripPageMock extends StatelessWidget {
  final Map<String, dynamic> requestData;
  const BookTripPageMock({Key? key, required this.requestData}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final pickup = requestData['pickup_address'] ?? '${requestData['pickup_lat']}, ${requestData['pickup_lng']}';
    final dest = requestData['destination_address'] ?? '${requestData['destination_lat']}, ${requestData['destination_lng']}';
    return Scaffold(
      appBar: AppBar(title: const Text('Request Preview')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Text('Pickup: $pickup'),
            const SizedBox(height: 12),
            Text('Destination: $dest'),
            const SizedBox(height: 12),
            Text('Fare: ${requestData['estimated_fare'] ?? '-'}'),
            const SizedBox(height: 12),
            Text('Distance: ${requestData['distance_km'] ?? '-'}'),
          ],
        ),
      ),
    );
  }
}
