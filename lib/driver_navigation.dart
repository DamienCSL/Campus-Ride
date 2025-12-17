// lib/driver_navigation.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

const String GOOGLE_API_KEY = 'AIzaSyBdppGmzFDFPxllShF0rQQXQ-nQVQdIB-Y';

class DriverNavigationPage extends StatefulWidget {
  final Map<String, dynamic> ride;

  const DriverNavigationPage({Key? key, required this.ride}) : super(key: key);

  @override
  State<DriverNavigationPage> createState() => _DriverNavigationPageState();
}

class _DriverNavigationPageState extends State<DriverNavigationPage> {
  final supabase = Supabase.instance.client;
  GoogleMapController? _mapController;

  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};
  LatLng? _currentPosition;

  List<LatLng> _fullRoutePath = [];
  double _nextWaypointDistance = 0;
  bool _showCompleteSticky = false;
  bool _isCompletingRide = false;

  // Navigation step-by-step variables
  List<Map<String, dynamic>> _navigationSteps = [];
  int _currentStepIndex = 0;
  String _currentInstruction = 'Starting navigation...';

  Timer? _locationTimer;
  RealtimeChannel? _rideChannel;

  @override
  void initState() {
    super.initState();
    _initNavigation();
    _subscribeToRideStatus();
  }

  @override
  void dispose() {
    _locationTimer?.cancel();
    if (_rideChannel != null) {
      try {
        supabase.removeChannel(_rideChannel!);
      } catch (_) {}
    }
    _mapController?.dispose();
    super.dispose();
  }

  void _subscribeToRideStatus() {
    final rideId = widget.ride['id']?.toString();
    if (rideId == null) return;

    _rideChannel = supabase
        .channel('public:rides:navigation:$rideId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'rides',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: rideId,
          ),
          callback: (payload) {
            final status = payload.newRecord['status']?.toString() ?? '';
            debugPrint('🛰️ [Nav] Ride status update: $status');
            if (status == 'completed' || status == 'cancelled') {
              // Exit navigation when ride ends
              if (mounted) {
                Navigator.pop(context);
              }
            }
          },
        )
        .subscribe();
  }

  Future<void> _initNavigation() async {
    await _getCurrentLocation();
    await _fetchAndDrawRoute();
    _startLocationTracking();
  }

  Future<void> _getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (mounted) {
        setState(() {
          _currentPosition = LatLng(position.latitude, position.longitude);
        });
        _updateMapMarkers();

        // Update driver location in database
        await _updateDriverLocation(position.latitude, position.longitude);

        // Animate camera to follow driver
        _mapController?.animateCamera(
          CameraUpdate.newLatLng(LatLng(position.latitude, position.longitude)),
        );
      }
    } catch (e) {
      debugPrint('Error getting location: $e');
    }
  }

  void _startLocationTracking() {
    _locationTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      await _getCurrentLocation();
      _updateNavigationProgress();

      // Auto exit if near destination and ride already completed elsewhere
      if (_currentPosition != null) {
        final destLat = _toDouble(widget.ride['destination_lat']);
        final destLng = _toDouble(widget.ride['destination_lng']);
        final distance = Geolocator.distanceBetween(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          destLat,
          destLng,
        );
        if (distance <= 80) {
          // If polylines remain, trim aggressively
          _trimPolylineProgress();

          // Show sticky Complete Ride button once when near destination and not arriving to pickup
          final isGoingToPickup = widget.ride['status'] == 'arriving';
          if (!isGoingToPickup && !_showCompleteSticky && mounted) {
            setState(() {
              _showCompleteSticky = true;
            });
          }
        }
      }
    });
  }

  Future<void> _updateDriverLocation(double lat, double lng) async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      await supabase.from('driver_locations').insert({
        'driver_id': userId,
        'lat': lat,
        'lng': lng,
        'recorded_at': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error updating driver location: $e');
    }
  }

  Future<void> _fetchAndDrawRoute() async {
    if (_currentPosition == null) return;

    final pickupLat = _toDouble(widget.ride['pickup_lat']);
    final pickupLng = _toDouble(widget.ride['pickup_lng']);
    final destLat = _toDouble(widget.ride['destination_lat']);
    final destLng = _toDouble(widget.ride['destination_lng']);

    final pickup = LatLng(pickupLat, pickupLng);
    final destination = LatLng(destLat, destLng);

    // Route from current position to pickup or destination based on ride status
    final isGoingToPickup = widget.ride['status'] == 'arriving';
    final targetLocation = isGoingToPickup ? pickup : destination;

    try {
      final points = await _fetchRoutePolyline(
        _currentPosition!,
        targetLocation,
      );

      if (points.isNotEmpty && mounted) {
        setState(() {
          _fullRoutePath = points;

          _polylines.clear();
          _polylines.add(
            Polyline(
              polylineId: const PolylineId('navigation_route'),
              points: points,
              color: Colors.blue,
              width: 6,
            ),
          );
        });

        // Fetch turn-by-turn navigation steps
        await _fetchNavigationSteps(_currentPosition!, targetLocation);
      }
    } catch (e) {
      debugPrint('Error fetching route: $e');
    }
  }

  Future<List<LatLng>> _fetchRoutePolyline(LatLng origin, LatLng dest) async {
    if (GOOGLE_API_KEY.isEmpty) return [];

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
    } catch (e) {
      debugPrint('Error fetching polyline: $e');
    }
    return [];
  }

  Future<void> _fetchNavigationSteps(LatLng origin, LatLng dest) async {
    if (GOOGLE_API_KEY.isEmpty) {
      debugPrint('Google API key not set. Skipping navigation steps request.');
      return;
    }

    try {
      final originStr = '${origin.latitude},${origin.longitude}';
      final destStr = '${dest.latitude},${dest.longitude}';
      final url =
          'https://maps.googleapis.com/maps/api/directions/json?origin=$originStr&destination=$destStr&mode=driving&key=$GOOGLE_API_KEY';

      final res = await http.get(Uri.parse(url));
      if (res.statusCode != 200) {
        debugPrint('Directions API returned HTTP ${res.statusCode}');
        return;
      }

      final data = json.decode(res.body) as Map<String, dynamic>;
      final status = data['status'] as String?;

      if (status != 'OK') {
        debugPrint('Directions API status: $status');
        return;
      }

      final routes = data['routes'] as List<dynamic>?;
      if (routes == null || routes.isEmpty) return;

      final route = routes.first as Map<String, dynamic>;
      final legs = route['legs'] as List<dynamic>?;
      if (legs == null || legs.isEmpty) return;

      // Extract all steps from all legs
      _navigationSteps.clear();
      int stepNum = 0;
      for (var leg in legs) {
        final steps = leg['steps'] as List<dynamic>?;
        if (steps == null) continue;

        for (var step in steps) {
          final instruction = step['html_instructions'] as String?;
          final distance = step['distance']['value'] as int?; // in meters
          final duration = step['duration']['value'] as int?; // in seconds
          final location = step['start_location'] as Map<String, dynamic>?;

          if (instruction != null && location != null) {
            // Strip HTML tags from instruction
            final cleanInstruction = instruction.replaceAll(
              RegExp(r'<[^>]*>'),
              '',
            );

            // Simplify instruction to be more driver-friendly
            final simplifiedInstruction = _simplifyInstruction(cleanInstruction);

            _navigationSteps.add({
              'number': stepNum++,
              'instruction': simplifiedInstruction,
              'distance': distance ?? 0,
              'duration': duration ?? 0,
              'location': LatLng(
                (location['lat'] as num).toDouble(),
                (location['lng'] as num).toDouble(),
              ),
            });
          }
        }
      }

      debugPrint('Fetched ${_navigationSteps.length} navigation steps');
      setState(() {
        _currentStepIndex = 0;
        if (_navigationSteps.isNotEmpty) {
          _currentInstruction = _navigationSteps[0]['instruction'];
        }
      });
    } catch (e) {
      debugPrint('Navigation steps error: $e');
    }
  }

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

  /// Simplify navigation instruction to be short and driver-friendly
  /// Examples: "Turn left on Jalan Sultan Ismail" → "Turn left on Jalan Sultan Ismail"
  ///           "Head south on Main Street" → "Go straight on Main Street"
  ///           "Slight right turn" → "Turn right"
  String _simplifyInstruction(String instruction) {
    // Remove excessive whitespace
    String simplified = instruction.replaceAll(RegExp(r'\s+'), ' ').trim();

    // Common simplifications
    simplified = simplified
        .replaceAll(RegExp(r'^Head\s+(north|south|east|west|northeast|northwest|southeast|southwest)\s+'), 'Go straight ')
        .replaceAll(RegExp(r'^Slight\s+left'), 'Turn left')
        .replaceAll(RegExp(r'^Slight\s+right'), 'Turn right')
        .replaceAll('(Unnamed Road)', 'this road')
        .replaceAll(RegExp(r'\s*\(.*?\)\s*'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Extract turn type + street name for brevity
    // Try to keep it under 50 characters
    if (simplified.length > 60) {
      // Extract pattern like "Turn left on Jalan xxx"
      final turnMatch = RegExp(r'(Turn (left|right)|Go straight|Continue|Take|Merge|Exit|Enter)\s+(?:on|onto|to)?\s+(.+?)(\s+towards|\s+in\s+|\s+at\s+|$)')
          .firstMatch(simplified);
      
      if (turnMatch != null) {
        final action = turnMatch.group(1) ?? 'Continue';
        var street = turnMatch.group(3) ?? 'this road';
        
        // Limit street name to ~40 chars
        if (street.length > 40) {
          street = street.substring(0, 40).trim() + '...';
        }
        
        simplified = '$action $street'.replaceAll(RegExp(r'\s+'), ' ').trim();
      }
    }

    // Final trim to remove junk at the end
    if (simplified.endsWith('then')) {
      simplified = simplified.substring(0, simplified.length - 4).trim();
    }

    return simplified.isEmpty ? 'Continue' : simplified;
  }

  void _updateMapMarkers() {
    if (_currentPosition == null) return;

    final pickupLat = _toDouble(widget.ride['pickup_lat']);
    final pickupLng = _toDouble(widget.ride['pickup_lng']);
    final destLat = _toDouble(widget.ride['destination_lat']);
    final destLng = _toDouble(widget.ride['destination_lng']);

    setState(() {
      _markers = {
        Marker(
          markerId: const MarkerId('current_position'),
          position: _currentPosition!,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen,
          ),
          infoWindow: const InfoWindow(title: 'Your Location'),
        ),
        Marker(
          markerId: const MarkerId('pickup'),
          position: LatLng(pickupLat, pickupLng),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          infoWindow: const InfoWindow(title: 'Pickup'),
        ),
        Marker(
          markerId: const MarkerId('destination'),
          position: LatLng(destLat, destLng),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: 'Destination'),
        ),
      };
    });
  }

  void _updateNavigationProgress() {
    if (_navigationSteps.isEmpty || _currentPosition == null) return;

    // Find closest step based on distance
    double closestDistance = double.infinity;
    int closestStepIndex = _currentStepIndex;

    for (int i = _currentStepIndex; i < _navigationSteps.length; i++) {
      final step = _navigationSteps[i];
      final stepLocation = step['location'] as LatLng;
      final distance = Geolocator.distanceBetween(
        _currentPosition!.latitude,
        _currentPosition!.longitude,
        stepLocation.latitude,
        stepLocation.longitude,
      );

      if (distance < closestDistance) {
        closestDistance = distance;
        closestStepIndex = i;
      } else {
        break; // Distance is increasing, stop searching
      }
    }

    // If we've moved to a new step, advance the instruction and trim polyline
    if (closestStepIndex > _currentStepIndex) {
      setState(() {
        _currentStepIndex = closestStepIndex;
        if (_currentStepIndex < _navigationSteps.length) {
          _currentInstruction =
              _navigationSteps[_currentStepIndex]['instruction'];
          _nextWaypointDistance = closestDistance;
        }

        // Trim polyline: remove all points that are "behind" or very close to current position
        _trimPolylineProgress();
      });
    } else {
      setState(() {
        _nextWaypointDistance = closestDistance;
      });
    }
  }

  /// Trim polyline to remove segments already traveled
  void _trimPolylineProgress() {
    if (_currentPosition == null || _polylines.isEmpty) return;

    // Collect updated polylines
    final updatedPolylines = <Polyline>[];
    for (final polyline in _polylines) {
      if (polyline.points.isEmpty) continue;

      // Find the first point that is still "ahead" of the driver (>50m away)
      int trimIndex = 0;
      for (int i = 0; i < polyline.points.length; i++) {
        final distance = Geolocator.distanceBetween(
          _currentPosition!.latitude,
          _currentPosition!.longitude,
          polyline.points[i].latitude,
          polyline.points[i].longitude,
        );
        if (distance > 50) {
          trimIndex = i;
          break;
        }
        trimIndex = i;
      }

      // Create new polyline with trimmed points
      if (trimIndex < polyline.points.length) {
        final remainingPoints = polyline.points.sublist(trimIndex);
        if (remainingPoints.isNotEmpty) {
          updatedPolylines.add(
            Polyline(
              polylineId: polyline.polylineId,
              points: remainingPoints,
              color: polyline.color,
              width: polyline.width,
            ),
          );
        }
      }
    }

    // Update the polylines set
    if (updatedPolylines.isNotEmpty) {
      _polylines.clear();
      _polylines.addAll(updatedPolylines);
    }
  }

  double _calculateDistance(LatLng from, LatLng to) {
    const double R = 6371000; // Earth radius in meters
    final lat1 = from.latitude * (pi / 180);
    final lat2 = to.latitude * (pi / 180);
    final dLat = (to.latitude - from.latitude) * (pi / 180);
    final dLng = (to.longitude - from.longitude) * (pi / 180);

    final a =
        sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1) * cos(lat2) * sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return R * c;
  }

  String _formatDistance(double meters) {
    if (meters < 1000) {
      return '${meters.toInt()} m';
    } else {
      return '${(meters / 1000).toStringAsFixed(1)} km';
    }
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  // Get direction arrow icon based on turn type
  IconData _getDirectionArrow() {
    final instruction = _currentInstruction.toLowerCase();

    if (instruction.contains('turn left')) {
      return Icons.turn_left;
    } else if (instruction.contains('turn right')) {
      return Icons.turn_right;
    } else if (instruction.contains('u-turn') ||
        instruction.contains('uturn') ||
        instruction.contains('turn around')) {
      return Icons.u_turn_right;
    } else if (instruction.contains('go straight') ||
        instruction.contains('continue')) {
      return Icons.straight;
    }
    return Icons.navigation;
  }

  bool _isNearDestination() {
    if (_currentPosition == null) return false;
    final destLat = _toDouble(widget.ride['destination_lat']);
    final destLng = _toDouble(widget.ride['destination_lng']);
    final distance = Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      destLat,
      destLng,
    );
    return distance <= 120; // slightly relaxed threshold for showing button
  }

  Future<void> _completeRide() async {
    if (_isCompletingRide) return;
    
    // Show confirmation dialog matching driver_dashboard pattern
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.check_circle_outline, color: Colors.green[700], size: 28),
            const SizedBox(width: 12),
            const Text('Complete Trip?'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Have you arrived at the destination?',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Row(
                children: [
                  Icon(Icons.location_on, color: Colors.blue[700], size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'You are near the destination',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.blue[900],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '• Rider will be prompted to rate your service\n• Trip will be marked as completed',
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Not Yet',
              style: TextStyle(color: Colors.grey[700]),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[600],
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text(
              'Yes, Complete Trip',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isCompletingRide = true);
    try {
      final rideId = widget.ride['id'];
      if (rideId == null) throw Exception('Ride ID missing');

      debugPrint('📝 [Navigation] Completing ride $rideId');
      
      await supabase.from('rides').update({
        'status': 'completed',
        'completed_at': DateTime.now().toIso8601String(),
      }).eq('id', rideId.toString());

      debugPrint('✅ [Navigation] Ride completed successfully');

      // Send notification to rider
      final riderId = widget.ride['rider_id'];
      if (riderId != null) {
        await supabase.from('notifications').insert({
          'user_id': riderId,
          'title': '✓ Trip Completed',
          'body': 'You have arrived at your destination. Thank you for riding with us!',
          'type': 'ride',
          'data': {
            'ride_id': rideId.toString(),
            'status': 'completed',
          },
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      if (!mounted) return;
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Trip completed successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      // Pop navigation screen after short delay
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) Navigator.pop(context);
      });
    } catch (e) {
      debugPrint('❌ [Navigation] Error completing ride: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to complete ride: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isCompletingRide = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const campusGreen = Color(0xFF00BFA6);

    return WillPopScope(
      onWillPop: () async {
        // Confirm before leaving navigation
        final shouldPop = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Exit Navigation?'),
            content: const Text('Are you sure you want to exit navigation?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Stay'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('Exit'),
              ),
            ],
          ),
        );
        return shouldPop ?? false;
      },
      child: Scaffold(
        body: Stack(
          children: [
            // Map (full screen)
            GoogleMap(
              initialCameraPosition: CameraPosition(
                target: _currentPosition ?? const LatLng(0, 0),
                zoom: 15,
              ),
              markers: _markers,
              polylines: _polylines,
              myLocationEnabled: true,
              myLocationButtonEnabled: true,
              onMapCreated: (controller) {
                _mapController = controller;
                if (_currentPosition != null) {
                  controller.animateCamera(
                    CameraUpdate.newLatLng(_currentPosition!),
                  );
                }
              },
            ),

            // Top close button
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              right: 16,
              child: FloatingActionButton(
                backgroundColor: Colors.white,
                onPressed: () => Navigator.pop(context),
                child: const Icon(Icons.close, color: Colors.black),
              ),
            ),

            // Bottom Waze-style navigation panel
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(
                    top: BorderSide(color: Colors.grey.shade300, width: 1),
                  ),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Direction arrow circle
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: campusGreen.withOpacity(0.1),
                            shape: BoxShape.circle,
                            border: Border.all(color: campusGreen, width: 2),
                          ),
                          child: Icon(
                            _getDirectionArrow(),
                            size: 40,
                            color: campusGreen,
                          ),
                        ),
                        const SizedBox(width: 16),

                        // Distance and instruction
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _formatDistance(_nextWaypointDistance),
                                style: const TextStyle(
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _currentInstruction,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Step ${_currentStepIndex + 1}/${_navigationSteps.length}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // Sticky Complete Ride button
                    if (_showCompleteSticky && _isNearDestination()) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: _isCompletingRide ? null : _completeRide,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: campusGreen,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(Icons.flag),
                          label: Text(
                            _isCompletingRide ? 'Completing…' : 'Complete Ride',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
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
