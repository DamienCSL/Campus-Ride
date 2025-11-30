// lib/driver_dashboard.dart
// Driver Dashboard — Supabase Flutter v2 compatible
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';

import 'main.dart';
import 'login.dart';

final supabase = Supabase.instance.client;

class DriverDashboard extends StatefulWidget {
  const DriverDashboard({super.key});

  @override
  State<DriverDashboard> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard> {
  // basic driver/local UI state
  String driverName = "Driver";
  bool isOnline = false;

  // current ride + income
  Map<String, dynamic>? _currentRide;
  int _completedRides = 0;
  double _totalIncome = 0.0;

  // map + tracking
  late GoogleMapController _mapController;
  final Set<Marker> _markers = {};
  Timer? _trackingTimer;

  // realtime channel
  RealtimeChannel? _rideChannel;

  @override
  void initState() {
    super.initState();
    loadDriverData();
    _fetchIncomeSummary();
    _fetchCurrentRide();
    _startTrackingDriverLocation();
    _subscribeToRideUpdates();
  }

  @override
  void dispose() {
    _trackingTimer?.cancel();
    if (_rideChannel != null) {
      try {
        supabase.removeChannel(_rideChannel!);
      } catch (_) {}
    }
    super.dispose();
  }

  // ------------------------- Local prefs -------------------------
  Future<void> loadDriverData() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();

    setState(() {
      driverName = prefs.getString("driver_name") ?? "Driver";
      isOnline = prefs.getBool("driver_online_status") ?? false;
    });
  }

  // ------------------------- Toggle availability -------------------------
  Future<void> toggleAvailability(bool value) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool("driver_online_status", value);

    final user = supabase.auth.currentUser;
    if (user != null) {
      try {
        await supabase.from("drivers").update({"active": value}).eq("id", user.id);
      } catch (e) {
        debugPrint("Failed to update driver active status: $e");
      }
    }

    setState(() => isOnline = value);
  }

  // ------------------------- Income summary -------------------------
  Future<void> _fetchIncomeSummary() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final resp = await supabase
          .from('rides')
          .select('fare')
          .eq('driver_id', user.id)
          .eq('status', 'completed');

      if (resp is List) {
        final List<Map<String, dynamic>> rides = List<Map<String, dynamic>>.from(resp);
        setState(() {
          _completedRides = rides.length;
          _totalIncome = rides.fold(
              0.0, (sum, r) => sum + (r['fare'] as num? ?? 0).toDouble());
        });
      }
    } catch (e) {
      debugPrint('Error fetching rides: $e');
    }
  }

  // ------------------------- Start tracking (write to DB periodically) -------------------------
  void _startTrackingDriverLocation() {
    _trackingTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      try {
        final user = supabase.auth.currentUser;
        if (user == null) return;

        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          return;
        }

        final pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high);

        await supabase.from('drivers').update({
          "current_lat": pos.latitude,
          "current_lng": pos.longitude,
        }).eq("id", user.id);

        await supabase.from('driver_locations').insert({
          "driver_id": user.id,
          "lat": pos.latitude,
          "lng": pos.longitude,
        });

        _markers.removeWhere((m) => m.markerId.value == 'driver_marker');
        _markers.add(Marker(
          markerId: const MarkerId('driver_marker'),
          position: LatLng(pos.latitude, pos.longitude),
          infoWindow: const InfoWindow(title: 'You'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        ));

        setState(() {});
      } catch (e) {
        debugPrint('Location update error: $e');
      }
    });
  }

  // ------------------------- Fetch current ride -------------------------
  Future<void> _fetchCurrentRide() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final resp = await supabase
          .from('rides')
          .select()
          .eq('driver_id', user.id)
          .neq('status', 'completed')
          .order('created_at', ascending: false)
          .limit(1);

      if (resp is List && resp.isNotEmpty) {
        setState(() => _currentRide = Map<String, dynamic>.from(resp.first));
        _updateMapMarkers();
      } else {
        setState(() => _currentRide = null);
      }
    } catch (e) {
      debugPrint('Error fetching current ride: $e');
    }
  }

  // ------------------------- Realtime subscription (v2 API) -------------------------
  void _subscribeToRideUpdates() {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    if (_rideChannel != null) {
      try {
        supabase.removeChannel(_rideChannel!);
      } catch (_) {}
      _rideChannel = null;
    }

    final channelName = 'public:rides:driver:${user.id}';
    _rideChannel = supabase.channel(channelName);

    _rideChannel!
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'rides',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'driver_id',
            value: user.id,
          ),
          callback: (payload) {
            final newData = payload.newRecord;
            if (newData == null) return;

            setState(() {
              _currentRide = Map<String, dynamic>.from(newData);
            });

            _updateMapMarkers();
            _fetchIncomeSummary();
          },
        )
        .subscribe();
  }

  // ------------------------- Map marker updates -------------------------
  void _updateMapMarkers() {
    _markers.removeWhere((m) => m.markerId.value == 'pickup');
    _markers.removeWhere((m) => m.markerId.value == 'destination');

    if (_currentRide != null) {
      final pickup = LatLng(
        (_currentRide!['pickup_lat'] ?? 0.0) as double,
        (_currentRide!['pickup_lng'] ?? 0.0) as double,
      );
      final destination = LatLng(
        (_currentRide!['destination_lat'] ?? 0.0) as double,
        (_currentRide!['destination_lng'] ?? 0.0) as double,
      );

      _markers.addAll([
        Marker(
          markerId: const MarkerId('pickup'),
          position: pickup,
          infoWindow: const InfoWindow(title: 'Pickup'),
        ),
        Marker(
          markerId: const MarkerId('destination'),
          position: destination,
          infoWindow: const InfoWindow(title: 'Destination'),
        ),
      ]);
    }

    setState(() {});
  }

  // ------------------------- Update ride status -------------------------
  Future<void> _updateRideStatus(String newStatus) async {
    if (_currentRide == null) return;

    try {
      await supabase.from('rides').update({
        'status': newStatus,
        'completed_at': newStatus == 'completed' ? DateTime.now().toIso8601String() : null,
      }).eq('id', _currentRide!['id']);

      await _fetchCurrentRide();
      await _fetchIncomeSummary();
    } catch (e) {
      debugPrint('Update ride error: $e');
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to update ride: $e')));
    }
  }

  // ------------------------- Trip button helper -------------------------
  String _getTripButtonLabel() {
    if (_currentRide == null) return 'No Ride';
    final status = _currentRide!['status'] as String?;
    switch (status) {
      case 'pending':
      case 'accepted':
        return 'Start Trip';
      case 'arriving':
      case 'ongoing':
        return 'Complete Trip';
      default:
        return 'No Ride';
    }
  }

  void _onTripButtonPressed() {
    if (_currentRide == null) return;
    final status = _currentRide!['status'] as String?;
    switch (status) {
      case 'pending':
      case 'accepted':
        _updateRideStatus('ongoing');
        break;
      case 'arriving':
      case 'ongoing':
        _updateRideStatus('completed');
        break;
    }
  }

  // ------------------------- Logout -------------------------
  Future<void> logout() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    await supabase.auth.signOut();

    if (!mounted) return;

    navigatorKey.currentState?.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const Login()), (route) => false);
  }

  // ------------------------- UI -------------------------
  @override
  Widget build(BuildContext context) {
    const campusGreen = Color(0xFF00BFA6);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Dashboard'),
        actions: [IconButton(icon: const Icon(Icons.logout), onPressed: logout)],
        backgroundColor: campusGreen,
      ),
      body: Column(
        children: [
          Expanded(
            flex: 2,
            child: GoogleMap(
              initialCameraPosition:
                  const CameraPosition(target: LatLng(3.1390, 101.6869), zoom: 12),
              markers: _markers,
              onMapCreated: (controller) => _mapController = controller,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
            ),
          ),
          Expanded(
            flex: 3,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Welcome back, $driverName',
                      style:
                          const TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Card(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  isOnline
                                      ? 'You are Online'
                                      : 'You are Offline',
                                  style: TextStyle(
                                      fontSize: 20,
                                      color: isOnline ? Colors.green : Colors.red)),
                              const SizedBox(height: 4),
                              Text(
                                  isOnline
                                      ? 'Passengers can request rides.'
                                      : 'You will not receive rides.',
                                  style: const TextStyle(fontSize: 14)),
                            ],
                          ),
                          Switch(
                              value: isOnline,
                              onChanged: toggleAvailability,
                              activeColor: campusGreen),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Current Ride:', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 6),
                  if (_currentRide != null)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                            'Pickup: ${_currentRide!['pickup_address']}\nDestination: ${_currentRide!['destination_address']}\nFare: RM${(_currentRide!['fare'] ?? 0).toString()}'),
                        const SizedBox(height: 8),
                        ElevatedButton(
                            onPressed: _onTripButtonPressed,
                            child: Text(_getTripButtonLabel())),
                      ],
                    )
                  else
                    const Text('No active ride.'),
                  const Divider(height: 30),
                  Text('Income Summary:', style: Theme.of(context).textTheme.titleMedium),
                  Text('Completed Rides: $_completedRides'),
                  Text('Total Income: RM${_totalIncome.toStringAsFixed(2)}'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
