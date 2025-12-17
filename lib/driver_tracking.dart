import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'ride_chat.dart';
import 'rating_dialog.dart';
import 'notification_overlay.dart';
import 'home.dart';

const String GOOGLE_API_KEY = 'AIzaSyBdppGmzFDFPxllShF0rQQXQ-nQVQdIB-Y';

class DriverTrackingPage extends StatefulWidget {
  final Map<String, dynamic> driver;
  final LatLng pickup;
  final LatLng destination;
  final String? rideId; // optional ride ID for chat

  const DriverTrackingPage({
    Key? key,
    required this.driver,
    required this.pickup,
    required this.destination,
    this.rideId,
  }) : super(key: key);

  @override
  State<DriverTrackingPage> createState() => _DriverTrackingPageState();
}

class _DriverTrackingPageState extends State<DriverTrackingPage>
    with TickerProviderStateMixin {
  late GoogleMapController _mapController;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};

  LatLng? _driverPos;
  Timer? _mockMoveTimer;
  double _distanceToPickup = 0;
  double _distanceToDestination = 0;

  // Driver display info
  String _driverName = 'Driver';
  String _vehicleInfo = 'Vehicle';
  String _plate = 'N/A';
  String _driverPhone = 'Not available';

  // animation controller for smooth movement
  AnimationController? _driverMoveController;
  Animation<LatLng>? _driverAnimation;

  RealtimeChannel? _rideSubscription;

  @override
  void initState() {
    super.initState();

    // seed display fields from provided map
    _driverName = widget.driver['full_name'] ?? widget.driver['name'] ?? 'Driver';
    _vehicleInfo = widget.driver['vehicle'] ?? 'Vehicle';
    _plate = widget.driver['plate'] ?? 'N/A';
    _driverPhone = widget.driver['phone'] ?? 'Not available';

    // Initialize with a default position, will be updated by live tracking
    _driverPos = LatLng(
      widget.pickup.latitude + 0.002,
      widget.pickup.longitude + 0.002,
    );

    _updateMarkers();
    _fetchAndDisplayRoutes();
    _loadInitialDriverLocation();
    _startMockLiveMovement();
    _listenForRideCompletion();
  }

  /// Load initial driver location from database
  Future<void> _loadInitialDriverLocation() async {
    final driverId = await _resolveDriverId();
    if (driverId == null) return;

    await _loadDriverProfileAndVehicle(driverId);

    try {
      final supabase = Supabase.instance.client;
      // Get the latest recorded point for this driver
      final locationDataList = await supabase
          .from('driver_locations')
          .select('lat, lng, recorded_at')
          .eq('driver_id', driverId)
          .order('recorded_at', ascending: false)
          .limit(1);

      if (locationDataList.isNotEmpty && mounted) {
        final locationData = locationDataList[0];
        debugPrint('[track] initial location: $locationData');
        setState(() {
          _driverPos = LatLng(
            (locationData['lat'] as num).toDouble(),
            (locationData['lng'] as num).toDouble(),
          );
          _updateMarkers();
          _moveCamera();
        });
      }
    } catch (e) {
      debugPrint('Error loading initial driver location: $e');
    }
  }

  @override
  void dispose() {
    _driverMoveController?.dispose();
    _mockMoveTimer?.cancel();
    if (_rideSubscription != null) {
      _rideSubscription!.unsubscribe();
    }
    super.dispose();
  }

  /// Listen for ride completion updates via Realtime
  void _listenForRideCompletion() {
    if (widget.rideId == null) {
      debugPrint('⚠️ [Tracking] No rideId provided, cannot listen for completion');
      return;
    }

    debugPrint('🔄 [Tracking] Setting up ride completion listener for ride ${widget.rideId}');
    final supabase = Supabase.instance.client;
    _rideSubscription = supabase
        .channel('rides:${widget.rideId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'rides',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.rideId,
          ),
          callback: (payload) {
            final newData = payload.newRecord;
            final status = newData['status'];
            debugPrint('🚗 [Tracking] Ride status update: $status');
            if (!mounted) return;
            if (status == 'completed') {
              debugPrint('✅ [Tracking] Ride completed, showing dialog');
              _showCompletionDialog();
            } else if (status == 'cancelled') {
              debugPrint('❌ [Tracking] Ride cancelled, exiting tracking');
              Navigator.of(context).pop(true);
            }
          },
        )
        .subscribe();
  }

  /// Resolve driver_id from widget or ride record and cache into widget.driver
  Future<String?> _resolveDriverId() async {
    String? driverId = widget.driver['driver_id'] ?? widget.driver['id'];

    if (driverId != null) {
      return driverId;
    }

    if (widget.rideId != null) {
      driverId = await _loadDriverIdFromRide();
    }

    return driverId;
  }

  /// Load driver profile and vehicle info to display real driver details
  Future<void> _loadDriverProfileAndVehicle(String driverId) async {
    try {
      final supabase = Supabase.instance.client;

      final profile = await supabase
          .from('profiles')
          .select('full_name, phone')
          .eq('id', driverId)
          .maybeSingle();

      final driverRow = await supabase
          .from('drivers')
          .select('vehicle_id')
          .eq('id', driverId)
          .maybeSingle();

      Map<String, dynamic>? vehicleRow;
      if (driverRow != null && driverRow['vehicle_id'] != null) {
        vehicleRow = await supabase
            .from('vehicles')
            .select('plate_number, model')
            .eq('id', driverRow['vehicle_id'])
            .maybeSingle();
      }

      if (!mounted) return;

      setState(() {
        _driverName = profile?['full_name'] ?? _driverName;
        _driverPhone = profile?['phone'] ?? _driverPhone;
        _vehicleInfo = vehicleRow?['model'] ?? _vehicleInfo;
        _plate = vehicleRow?['plate_number'] ?? _plate;
        // also update widget.driver for downstream uses like chat
        widget.driver['full_name'] = _driverName;
        widget.driver['name'] = _driverName;
        widget.driver['phone'] = _driverPhone;
        widget.driver['vehicle'] = _vehicleInfo;
        widget.driver['plate'] = _plate;
        widget.driver['id'] = widget.driver['id'] ?? driverId;
        widget.driver['driver_id'] = driverId;
      });

      debugPrint('[track] driver profile=$profile vehicle=$vehicleRow');
    } catch (e) {
      debugPrint('Error loading driver info: $e');
    }
  }

  /// Show completion pop-up when driver completes the trip
  void _showCompletionDialog() async {
    final supabase = Supabase.instance.client;
    final driverId = await _resolveDriverId();
    
    // Get driver info for rating
    String driverName = _driverName;
    String? driverAvatar;
    
    if (driverId != null) {
      try {
        final profile = await supabase
            .from('profiles')
            .select('full_name, avatar_url')
            .eq('id', driverId)
            .maybeSingle();
        if (profile != null) {
          driverName = profile['full_name']?.toString() ?? driverName;
          driverAvatar = profile['avatar_url']?.toString();
        }
      } catch (_) {}
    }

    if (!mounted) return;

    // Show completion message first
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('✓ Trip Completed'),
        content: const Text('You have arrived at your destination. Thank you for riding with us!'),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00BFA6),
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    // Then show rating dialog if we have ride and driver info
    if (widget.rideId != null && driverId != null) {
      final rated = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => RatingDialog(
          tripId: widget.rideId!,
          driverId: driverId,
          driverName: driverName,
          driverAvatar: driverAvatar,
        ),
      );
      
      debugPrint('✅ [Tracking] Rating dialog closed, rated: $rated');
    }

    // Navigate back to home page after rating - use pushAndRemoveUntil to clear stack
    if (mounted) {
      debugPrint('🏠 [Tracking] Navigating to home page');
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (context) => const Home()),
        (route) => false, // Remove all previous routes
      );
    }
  }

  /// Show driver phone number dialog
  void _showPhoneDialog() {
    final phone = _driverPhone;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Driver Contact'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _driverName,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.phone, size: 20, color: Color(0xFF00BFA6)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    phone,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  /// Calculate distance between two points using Haversine formula
  double _calculateDistance(LatLng from, LatLng to) {
    const double R = 6371; // Earth radius in km
    final lat1 = from.latitude * (pi / 180);
    final lat2 = to.latitude * (pi / 180);
    final dLat = (to.latitude - from.latitude) * (pi / 180);
    final dLng = (to.longitude - from.longitude) * (pi / 180);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c * 1000; // Return in meters
  }

  /// Fetch route polylines from Google Directions API
  Future<void> _fetchAndDisplayRoutes() async {
    try {
      // Route from driver to pickup (blue)
      final driverToPickupPoints = await _fetchRoutePolyline(_driverPos!, widget.pickup);
      if (driverToPickupPoints.isNotEmpty) {
        _polylines.add(
          Polyline(
            polylineId: const PolylineId('driver_to_pickup'),
            points: driverToPickupPoints,
            color: Colors.blue,
            width: 5,
          ),
        );
      }

      // Route from pickup to destination (green)
      final pickupToDestPoints = await _fetchRoutePolyline(widget.pickup, widget.destination);
      if (pickupToDestPoints.isNotEmpty) {
        _polylines.add(
          Polyline(
            polylineId: const PolylineId('pickup_to_dest'),
            points: pickupToDestPoints,
            color: Colors.green,
            width: 5,
          ),
        );
      }

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Error fetching routes: $e');
    }
  }

  /// Fetch polyline points from Google Directions API
  Future<List<LatLng>> _fetchRoutePolyline(LatLng origin, LatLng dest) async {
    if (GOOGLE_API_KEY.isEmpty) {
      debugPrint('Google API key not set');
      return [];
    }

    final originStr = '${origin.latitude},${origin.longitude}';
    final destStr = '${dest.latitude},${dest.longitude}';
    final url =
        'https://maps.googleapis.com/maps/api/directions/json?origin=$originStr&destination=$destStr&mode=driving&key=$GOOGLE_API_KEY';

    try {
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);
        if (json['status'] == 'OK') {
          final route = json['routes'][0];
          final overviewPolyline = route['overview_polyline']['points'];
          return _decodePolyline(overviewPolyline);
        }
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching polyline: $e');
      return [];
    }
  }

  /// Decode polyline string from Google Maps
  List<LatLng> _decodePolyline(String encoded) {
    List<LatLng> poly = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0) ? ~(result >> 1) : (result >> 1);
      lng += dlng;

      poly.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return poly;
  }

  Future<void> _startMockLiveMovement() async {
    // Always refresh driver_id from the ride when possible
    String? driverIdFromRide;
    if (widget.rideId != null) {
      driverIdFromRide = await _loadDriverIdFromRide();
    }

    final resolvedDriverId = driverIdFromRide ?? widget.driver['driver_id'] ?? widget.driver['id'];
    if (resolvedDriverId != null) {
      await _loadDriverProfileAndVehicle(resolvedDriverId);
    }

    // Poll driver location from driver_locations table every 3 seconds
    _mockMoveTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (!mounted) {
        timer.cancel();
        return;
      }

      // Use driverId from widget if available (populated from ride when present)
      String? currentDriverId = widget.driver['driver_id'] ?? widget.driver['id'];
      if (currentDriverId == null) return;

      try {
        final supabase = Supabase.instance.client;
        // Always fetch the most recent location for this driver
        final locationDataList = await supabase
            .from('driver_locations')
            .select('lat, lng, recorded_at')
            .eq('driver_id', currentDriverId)
            .order('recorded_at', ascending: false)
            .limit(1);

        if (locationDataList.isNotEmpty && mounted) {
          final locationData = locationDataList[0];
          debugPrint('[track] poll location for $currentDriverId: $locationData');
          final newPos = LatLng(
            (locationData['lat'] as num).toDouble(),
            (locationData['lng'] as num).toDouble(),
          );

          // Only update if position changed significantly (more than 1 meter)
          if (_driverPos != null) {
            final distance = _calculateDistance(_driverPos!, newPos);
            if (distance > 1) {
              _animateDriver(_driverPos!, newPos, duration: 2000);
              _driverPos = newPos;
            }
          } else {
            _driverPos = newPos;
          }

          // Update distances
          _distanceToPickup = _calculateDistance(_driverPos!, widget.pickup);
          _distanceToDestination = _calculateDistance(_driverPos!, widget.destination);

          setState(() {
            _updateMarkers();
          });
        }
      } catch (e) {
        debugPrint('Error fetching driver location: $e');
      }
    });
  }

  /// Load driver ID from ride if not available
  Future<String?> _loadDriverIdFromRide() async {
    if (widget.rideId == null) return null;

    try {
      final supabase = Supabase.instance.client;
      final rideData = await supabase
          .from('rides')
          .select('driver_id')
          .eq('id', widget.rideId!)
          .maybeSingle();
      
      if (rideData != null && rideData['driver_id'] != null && mounted) {
        // Update widget driver with the actual driver_id
        widget.driver['driver_id'] = rideData['driver_id'];
        widget.driver['id'] = widget.driver['id'] ?? rideData['driver_id'];
        return rideData['driver_id'] as String;
      }
    } catch (e) {
      debugPrint('Error fetching driver from ride: $e');
    }

    return null;
  }

  void _animateDriver(LatLng from, LatLng to, {int duration = 500}) {
    _driverMoveController?.dispose();
    _driverMoveController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: duration),
    );

    _driverAnimation = LatLngTween(begin: from, end: to).animate(_driverMoveController!)
      ..addListener(() {
        if (mounted) {
          setState(() {
            _driverPos = _driverAnimation!.value;
            _updateMarkers();
            _moveCamera();
          });
        }
      });

    _driverMoveController!.forward();
  }

  void _updateMarkers() {
    _markers = {
      Marker(
        markerId: const MarkerId('pickup'),
        position: widget.pickup,
        infoWindow: const InfoWindow(title: "Pickup Location"),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
      ),
      Marker(
        markerId: const MarkerId('destination'),
        position: widget.destination,
        infoWindow: const InfoWindow(title: "Destination"),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      ),
      Marker(
        markerId: const MarkerId('driver'),
        position: _driverPos!,
        infoWindow: const InfoWindow(title: "Driver"),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
      ),
    };
  }

  void _moveCamera() {
    if (!mounted) return;
    try {
      // compute midpoint between driver & pickup for smooth tracking
      final midLat = (_driverPos!.latitude + widget.pickup.latitude) / 2;
      final midLng = (_driverPos!.longitude + widget.pickup.longitude) / 2;

      _mapController.animateCamera(
        CameraUpdate.newLatLng(LatLng(midLat, midLng)),
      );
    } catch (e) {
      debugPrint('Camera error: $e');
    }
  }

  /// Format distance for display
  String _formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.toInt()} m';
    } else {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
  }

  @override
  Widget build(BuildContext context) {
    const campusGreen = Color(0xFF00BFA6);
    final driverName = _driverName;
    final vehicleInfo = _vehicleInfo;
    final plate = _plate;

    return Scaffold(
      appBar: AppBar(
        title: Text("Tracking $driverName"),
        backgroundColor: campusGreen,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: NotificationOverlay(
        child: Stack(
          children: [
          // Full-page map with polylines
          GoogleMap(
            initialCameraPosition:
                CameraPosition(target: widget.pickup, zoom: 15),
            markers: _markers,
            polylines: _polylines,
            onMapCreated: (c) => _mapController = c,
            myLocationEnabled: false,
          ),
          // Bottom info panel
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(
                    top: BorderSide(color: Colors.grey.shade300, width: 1)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Driver info row
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 30,
                        backgroundColor: Colors.grey[300],
                        child: const Icon(Icons.person, size: 30),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              driverName,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '$vehicleInfo • $plate',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _formatDistance(_distanceToPickup),
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                          const Text(
                            'to pickup',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Route info
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: Colors.blue,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: const Text('Driver to Pickup',
                                        style: TextStyle(fontSize: 12),
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Container(
                                    width: 12,
                                    height: 12,
                                    decoration: BoxDecoration(
                                      color: Colors.green,
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: const Text('Pickup to Destination',
                                        style: TextStyle(fontSize: 12),
                                        overflow: TextOverflow.ellipsis),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _formatDistance(_distanceToPickup),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _formatDistance(_distanceToDestination),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: widget.rideId != null
                              ? () {
                                  final currentUser =
                                      Supabase.instance.client.auth.currentUser;
                                  final driverId = (widget.driver['driver_id'] ?? widget.driver['id'])?.toString() ?? '';
                                  if (currentUser != null && driverId.isNotEmpty) {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => RideChatPage(
                                          rideId: widget.rideId!,
                                          myUserId: currentUser.id,
                                          peerUserId: driverId,
                                          peerName: driverName,
                                        ),
                                      ),
                                    );
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Driver information not available')),
                                    );
                                  }
                                }
                              : null,
                          icon: const Icon(Icons.message),
                          label: const Text("Chat"),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _showPhoneDialog,
                          style: ElevatedButton.styleFrom(
                              backgroundColor: campusGreen),
                          icon: const Icon(Icons.call),
                          label: const Text("Call"),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      ),
    );
  }
}

/// Simple LatLngTween for smooth marker movement
class LatLngTween extends Tween<LatLng> {
  LatLngTween({required LatLng begin, required LatLng end})
      : super(begin: begin, end: end);

  @override
  LatLng lerp(double t) => LatLng(
        begin!.latitude + (end!.latitude - begin!.latitude) * t,
        begin!.longitude + (end!.longitude - begin!.longitude) * t,
      );
}

