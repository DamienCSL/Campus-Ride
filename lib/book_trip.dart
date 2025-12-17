// lib/book_trip.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_places_flutter/google_places_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'driver_tracking.dart';
import 'error_handler.dart';
import 'notification_service.dart';

/// Single-file Booking screen (Grab-style)
/// Replace API_KEY with your Google API Key (same key you put in AndroidManifest).
class BookTripPage extends StatefulWidget {
  const BookTripPage({Key? key}) : super(key: key);

  @override
  State<BookTripPage> createState() => _BookTripPageState();
}

class _BookTripPageState extends State<BookTripPage> {
  // === CONFIG ===
  static const String API_KEY = 'AIzaSyBdppGmzFDFPxllShF0rQQXQ-nQVQdIB-Y';

  // === MAP / CONTROLLERS ===
  late GoogleMapController _mapController;
  final CameraPosition _initialCamera = const CameraPosition(
    target: LatLng(5.9804, 116.0735),
    zoom: 14,
  );

  // controllers for text fields (read-only UI, open bottom sheet to edit)
  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();

  // state
  LatLng? _pickupLatLng;
  LatLng? _destinationLatLng;

  bool _pickupLocked =
      false; // hard lock: disable auto-updates permanently after confirm
  bool _userManuallyPickedPickup =
      false; // temporary pause after manual pick (8s)
  bool _mapReady = false;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};

  // fare/distance/time
  double _distanceKm = 0.0;
  double _durationMin = 0.0;
  double _estimatedFare = 0.0;

  // debounce for camera idle reverse geocode
  Timer? _debounceReverse;

  // ----- Finding driver state -----
  bool _isFindingDriver = false;
  Timer? _findingTimer;
  int _findingSecondsLeft = 20; // countdown in seconds
  bool _driverFound = false;
  Map<String, dynamic>? _mockDriver; // when found
  String? _currentTripId; // store trip ID for driver tracking

  @override
  void initState() {
    super.initState();
    _initLocationAndCamera();
  }

  @override
  void dispose() {
    _pickupController.dispose();
    _destinationController.dispose();
    _debounceReverse?.cancel();
    _findingTimer?.cancel();
    super.dispose();
  }

  // Get permission and move camera to current location (best-effort)
  Future<void> _initLocationAndCamera() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
      final start = LatLng(pos.latitude, pos.longitude);

      // move camera after short delay (map may not be ready immediately)
      Future.delayed(const Duration(milliseconds: 300), () {
        try {
          _mapController.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(target: start, zoom: 16),
            ),
          );
        } catch (_) {}
      });

      // set initial pickup to current location (will be replaced if user drags)
      _pickupLatLng = start;
      _reverseGeocodeAndSetPickup(start, updateText: true);
      setState(() {});
    } catch (e) {
      // ignore - best effort
    }
  }

  // Reverse geocode latlng -> address
  Future<void> _reverseGeocodeAndSetPickup(
    LatLng latlng, {
    bool updateText = true,
  }) async {
    // do not update pickup if the pickup is locked (confirmed) OR hard-locked
    if (_pickupLocked) return;
    try {
      final url =
          'https://maps.googleapis.com/maps/api/geocode/json?latlng=${latlng.latitude},${latlng.longitude}&key=$API_KEY';
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        if (data['status'] == 'OK' &&
            data['results'] != null &&
            data['results'].isNotEmpty) {
          final formatted = data['results'][0]['formatted_address'] as String;
          if (updateText) {
            _pickupController.text = formatted;
          }
          _pickupLatLng = latlng;
          // update pickup marker visually for preview (not final until confirmed)
          _markers.removeWhere((m) => m.markerId.value == 'pickup_marker');
          _markers.add(
            Marker(
              markerId: const MarkerId('pickup_marker'),
              position: latlng,
              infoWindow: InfoWindow(title: 'Pickup', snippet: formatted),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueAzure,
              ),
            ),
          );
          setState(() {});
        }
      }
    } catch (e) {
      // ignore network failures silently (best-effort)
    }
  }

  // Get place details (lat/lng) from place_id (web HTTP Places API)
  Future<LatLng?> _getPlaceLatLngFromPlaceId(String placeId) async {
    try {
      final url =
          'https://maps.googleapis.com/maps/api/place/details/json?place_id=$placeId&key=$API_KEY';
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        if (data['status'] == 'OK' && data['result'] != null) {
          final geom = data['result']['geometry'];
          final loc = geom['location'];
          final lat = (loc['lat'] as num).toDouble();
          final lng = (loc['lng'] as num).toDouble();
          return LatLng(lat, lng);
        }
      }
    } catch (e) {
      // ignore
    }
    return null;
  }

  // Fetch directions and draw polyline; also compute distance/time/fare
  Future<void> _fetchRouteAndEstimate(LatLng origin, LatLng dest) async {
    try {
      final url =
          'https://maps.googleapis.com/maps/api/directions/json?origin=${origin.latitude},${origin.longitude}&destination=${dest.latitude},${dest.longitude}&key=$API_KEY&mode=driving';
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        if (data['status'] == 'OK' && (data['routes'] as List).isNotEmpty) {
          final route = data['routes'][0] as Map<String, dynamic>;
          final overview = route['overview_polyline']['points'] as String;
          final points = _decodePolyline(overview);

          // read first leg distance/duration
          if ((route['legs'] as List).isNotEmpty) {
            final leg = route['legs'][0];
            final distMeters = (leg['distance']['value'] as num).toDouble();
            final durationSec = (leg['duration']['value'] as num).toDouble();

            _distanceKm = distMeters / 1000.0;
            _durationMin = durationSec / 60.0;

            // Fare formula (example): base + per km + per minute
            const baseFare = 2.0;
            const perKm = 0.8;
            const perMin = 0.05;
            _estimatedFare =
                baseFare + (_distanceKm * perKm) + (_durationMin * perMin);
            // Round up to nearest 0.50 (e.g., 12.23 -> 12.50, 12.51 -> 13.00)
            _estimatedFare = (_estimatedFare * 2).ceil() / 2.0;
          }

          // clear previous route and add new
          _polylines.clear();
          _polylines.add(
            Polyline(
              polylineId: const PolylineId('route'),
              points: points,
              width: 6,
              color: Colors.blue,
            ),
          );

          // ensure stable destination marker at chosen lat/lng
          _markers.removeWhere(
            (m) =>
                m.markerId.value == 'dest_marker' ||
                (m.infoWindow.title == 'Destination'),
          );
          _markers.add(
            Marker(
              markerId: const MarkerId('dest_marker'),
              position: dest,
              infoWindow: InfoWindow(
                title: 'Destination',
                snippet: _destinationController.text,
              ),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueRed,
              ),
            ),
          );

          setState(() {});

          // fit camera to route bounds
          _fitMapToPoints(points);
        } else {
          // no routes - clear previous polyline if any
          _polylines.clear();
          setState(() {});
        }
      }
    } catch (e) {
      // ignore
    }
  }

  // Save the trip to SUPABASE

  Future<String?> _saveTripToSupabase() async {
    final supabase = Supabase.instance.client;

    if (_pickupLatLng == null || _destinationLatLng == null) {
      return null;
    }

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        throw AppException(message: 'User not authenticated', code: 'no_auth');
      }

      // Cancel only 'open' ride_requests (not assigned ones which have a driver)
      // This prevents cancelling rides that have already been picked up by a driver
      await supabase
          .from('ride_requests')
          .update({'status': 'cancelled'})
          .eq('rider_id', userId)
          .eq('status', 'open');

      final response = await supabase
          .from('ride_requests')
          .insert({
            'rider_id': userId,
            'pickup_address': _pickupController.text,
            'pickup_lat': _pickupLatLng!.latitude,
            'pickup_lng': _pickupLatLng!.longitude,
            'destination_address': _destinationController.text,
            'destination_lat': _destinationLatLng!.latitude,
            'destination_lng': _destinationLatLng!.longitude,
            'estimated_fare': _estimatedFare,
            'distance_km': _distanceKm,
            'status': 'open',
            'requested_at': DateTime.now().toIso8601String(),
          })
          .select()
          .maybeSingle();

      return response?['id'];
    } on PostgrestException catch (e) {
      ErrorHandler.logError('_saveTripToSupabase', e);
      return null;
    } catch (e) {
      ErrorHandler.logError('_saveTripToSupabase', e);
      return null;
    }
  }

  Future<void> _fitMapToPoints(List<LatLng> points) async {
    if (points.isEmpty) return;
    double minLat = points.first.latitude, maxLat = points.first.latitude;
    double minLng = points.first.longitude, maxLng = points.first.longitude;
    for (var p in points) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );
    final padding = 80.0;
    try {
      await _mapController.animateCamera(
        CameraUpdate.newLatLngBounds(bounds, padding),
      );
    } catch (e) {
      // ignore if fails on emulator
    }
  }

  // Decode polyline algorithm
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

      final latitude = lat / 1e5;
      final longitude = lng / 1e5;
      poly.add(LatLng(latitude, longitude));
    }
    return poly;
  }

  // -------------- FIND DRIVER UI & LOGIC --------------

  void _startFindingDriver() async {
    if (_isFindingDriver) return;

    if (_pickupLatLng == null || _destinationLatLng == null) {
      ErrorHandler.showErrorSnackBar(
        context,
        'Please set both pickup and destination',
      );
      return;
    }

    setState(() {
      _isFindingDriver = true;
      _driverFound = false;
      _findingSecondsLeft = 20;
      _mockDriver = null;
    });

    // STEP 1: CREATE TRIP WITHOUT DRIVER
    final tripId = await _saveTripToSupabase();
    if (tripId == null) {
      if (!mounted) return;
      setState(() => _isFindingDriver = false);
      ErrorHandler.showErrorSnackBar(
        context,
        AppException(
          message: 'Failed to create trip request. Please try again.',
          code: 'trip_creation_failed',
        ),
      );
      return;
    }

    // Save trip ID to state for use in driver tracking
    _currentTripId = tripId;

    // STEP 2: OPEN BOTTOM SHEET
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            // STEP 3: START FINDING TIMER + POLLING FOR DRIVER ASSIGNMENT
            if (_findingTimer == null || !_findingTimer!.isActive) {
              _findingTimer?.cancel();
              _findingTimer = Timer.periodic(const Duration(seconds: 1), (
                timer,
              ) {
                if (!mounted) {
                  timer.cancel();
                  return;
                }

                // If driver was found, stop the timer immediately
                if (_driverFound) {
                  timer.cancel();
                  return;
                }

                setState(() => _findingSecondsLeft--);
                setSheetState(() {});

                // POLL: Check if a driver has been assigned to this ride_request
                _pollForDriverAssignment(tripId, setSheetState);

                // TIMEOUT
                if (_findingSecondsLeft <= 0) {
                  timer.cancel();
                  setState(() {
                    _isFindingDriver = false;
                    _driverFound = false;
                  });
                  setSheetState(() {});
                }
              });
            }

            // STEP 6: BOTTOM SHEET UI
            return AnimatedPadding(
              duration: const Duration(milliseconds: 200),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom,
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                padding: const EdgeInsets.all(16),
                child: _driverFound
                    ? _buildDriverFoundSheet(context, setSheetState)
                    : _findingSecondsLeft > 0
                    ? _buildFindingSheet(context, setSheetState)
                    : _buildNoDriverSheet(context, setSheetState),
              ),
            );
          },
        );
      },
    ).whenComplete(() {
      _findingTimer?.cancel();
      setState(() {
        _isFindingDriver = false;
        _driverFound = false;
      });
    });
  }

  // finding animation

  Widget _buildFindingSheet(BuildContext ctx, StateSetter setSheetState) {
    final progress = (20 - _findingSecondsLeft) / 20.0;
    const campusGreen = Color(0xFF00BFA6);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        Center(
          child: Container(
            width: 60,
            height: 6,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Finding nearby drivers...',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Searching for drivers • ${_findingSecondsLeft}s left',
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: () {
                // allow cancel
                _cancelFindingDriver();
                Navigator.of(ctx).pop();
              },
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        const SizedBox(height: 16),
        LinearProgressIndicator(value: progress),
        const SizedBox(height: 18),
        Text(
          'We are searching drivers near your pickup. This may take a few seconds.',
          style: TextStyle(color: Colors.grey[700]),
        ),
        const Spacer(),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  _cancelFindingDriver();
                  Navigator.of(ctx).pop();
                },
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: campusGreen),
              onPressed: () {
                // user wants to keep waiting — do nothing (UI already waiting)
              },
              child: const Text('Keep Searching'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildNoDriverSheet(BuildContext ctx, StateSetter setSheetState) {
    const campusGreen = Color(0xFF00BFA6);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        Center(
          child: Container(
            width: 60,
            height: 6,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'No drivers found nearby',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        const Text(
          'We couldn’t find any drivers around your pickup location. You can try again or adjust your pickup.',
        ),
        const Spacer(),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () {
                  // retry
                  Navigator.of(ctx).pop();
                  Future.delayed(
                    const Duration(milliseconds: 250),
                    _startFindingDriver,
                  );
                },
                child: const Text('Retry'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: campusGreen),
                onPressed: () {
                  Navigator.of(ctx).pop(); // close sheet
                },
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDriverFoundSheet(BuildContext ctx, StateSetter setSheetState) {
    const campusGreen = Color(0xFF00BFA6);
    final d = _mockDriver!;
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 6),
          Center(
            child: Container(
              width: 60,
              height: 6,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: Colors.grey[300],
                child: const Icon(Icons.person),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d['name'],
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${d['vehicle']} • ${d['plate']}',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
              Text(
                'ETA ${d['eta_min']}m',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 8),
          const Text(
            'Driver is on the way. You can message or call the driver, or track them on the map.',
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    // here you might navigate to chat or call flow
                    Navigator.of(ctx).pop();
                  },
                  child: const Text('Message'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: campusGreen),
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DriverTrackingPage(
                          driver: _mockDriver!,
                          pickup: _pickupLatLng!,
                          destination: _destinationLatLng!,
                          rideId: _currentTripId, // Pass the ride/trip ID for tracking
                        ),
                      ),
                    );
                  },

                  child: const Text('Track'),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _cancelActiveRideRequest();
            },
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: Colors.red.shade300),
            ),
            child: const Text(
              'Cancel Ride',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  void _cancelFindingDriver() {
    _findingTimer?.cancel();
    setState(() {
      _isFindingDriver = false;
      _driverFound = false;
      _findingSecondsLeft = 0;
      _mockDriver = null;
    });
  }

  Future<void> _cancelActiveRideRequest() async {
    final supabase = Supabase.instance.client;
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      // Get driver ID before cancelling to send notification
      String? driverId;
      if (_mockDriver != null) {
        driverId = _mockDriver!['driver_id'];
      }

      // Cancel open/accepted/arriving ride_requests for this rider
      await supabase
          .from('ride_requests')
          .update({
            'status': 'cancelled',
            'cancelled_at': DateTime.now().toIso8601String(),
          })
          .eq('rider_id', userId)
          .not('status', 'in', ['completed', 'cancelled']);

      // Cancel rides (if already created) still not completed
      await supabase
          .from('rides')
          .update({
            'status': 'cancelled',
            'cancelled_at': DateTime.now().toIso8601String(),
          })
          .eq('rider_id', userId)
          .not('status', 'in', ['completed', 'cancelled']);

      // Send notification to driver if assigned
      if (driverId != null) {
        NotificationService().createNotification(
          userId: driverId,
          title: 'Ride Cancelled',
          body: 'The rider has cancelled the ride',
          type: 'ride',
          data: {
            'ride_id': _currentTripId ?? '',
            'cancelled_by': 'rider',
          },
        );
      }

      // Reset UI state - keep pickup/destination, only reset finding state
      _findingTimer?.cancel();
      setState(() {
        _isFindingDriver = false;
        _driverFound = false;
        _findingSecondsLeft = 0;
        _mockDriver = null;
        // Keep _pickupLocked = false so user can modify pickup if needed after cancellation
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ride cancelled. You can request a new ride.')),
        );
        // Pop only the finding driver bottom sheet, keep the main page
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      }
    } catch (e) {
      ErrorHandler.logError('cancel_active_ride_request', e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to cancel ride: $e')),
        );
      }
    }
  }

  // Polling method to check if driver has been assigned
  Future<void> _pollForDriverAssignment(
    String tripId,
    StateSetter setSheetState,
  ) async {
    if (_driverFound) return; // Already found, don't poll again

    try {
      final supabase = Supabase.instance.client;
      debugPrint('[poll] tripId=$tripId');

        final rideRequest = await supabase
          .from('ride_requests')
          .select('assigned_driver')
          .eq('id', tripId)
          .maybeSingle();

        debugPrint('[poll] ride_request row: $rideRequest');

      if (rideRequest != null && rideRequest['assigned_driver'] != null) {
        final assignedDriverId = rideRequest['assigned_driver'] as String;
        debugPrint('[poll] driver assigned: $assignedDriverId');

        // Fetch driver details from profiles table
        final driverProfileResponse = await supabase
            .from('profiles')
            .select('full_name, phone')
            .eq('id', assignedDriverId);

        debugPrint('[poll] profile: $driverProfileResponse');

        String driverName = 'Driver';
        String driverPhone = 'Not available';
        if (driverProfileResponse.isNotEmpty) {
          driverName = driverProfileResponse[0]['full_name'] ?? 'Driver';
          driverPhone = driverProfileResponse[0]['phone'] ?? 'Not available';
          debugPrint('Driver name found: $driverName, Phone: $driverPhone');
        }

        // Fetch vehicle info through drivers table
        final driverVehicleResponse = await supabase
            .from('drivers')
            .select('vehicle_id')
            .eq('id', assignedDriverId);

        debugPrint('[poll] driver row: $driverVehicleResponse');

        String vehicleModel = 'Vehicle';
        String plateName = 'N/A';

        if (driverVehicleResponse.isNotEmpty) {
          final vehicleId = driverVehicleResponse[0]['vehicle_id'];
          debugPrint('Vehicle ID: $vehicleId');

          if (vehicleId != null) {
            final vehicleResponse = await supabase
                .from('vehicles')
                .select('plate_number, model')
                .eq('id', vehicleId);

            debugPrint('[poll] vehicle: $vehicleResponse');

            if (vehicleResponse.isNotEmpty) {
              vehicleModel = vehicleResponse[0]['model'] ?? 'Vehicle';
              plateName = vehicleResponse[0]['plate_number'] ?? 'N/A';
              debugPrint(
                'Vehicle details - Model: $vehicleModel, Plate: $plateName',
              );
            }
          }
        }

        // Stop timer and update state (use fallback names if data not found)
        _findingTimer?.cancel();
        setState(() {
          _driverFound = true;
          _isFindingDriver = false;
          _findingSecondsLeft = 0;

          _mockDriver = {
            'full_name': driverName,
            'phone': driverPhone,
            'name': driverName,
            'vehicle': vehicleModel,
            'plate': plateName,
            'eta_min': 4,
            'driver_id': assignedDriverId,
          };
        });
        debugPrint('[poll] driver card payload: $_mockDriver');
        
        // Send notification to user
        final userId = supabase.auth.currentUser?.id;
        if (userId != null) {
          NotificationService().createNotification(
            userId: userId,
            title: 'Driver Found!',
            body: '$driverName is on the way with $vehicleModel ($plateName)',
            type: 'ride',
            data: {
              'driver_id': assignedDriverId,
              'trip_id': tripId,
            },
          );
        }
        
        setSheetState(() {});
      }
    } catch (e) {
      debugPrint('Polling error: $e');
    }
  }

  // -------------- UI & Handlers --------------

  @override
  Widget build(BuildContext context) {
    const campusGreen = Color(0xFF00BFA6);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Book a Ride'),
        backgroundColor: campusGreen,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Stack(
        children: [
          // Google Map
          GoogleMap(
            initialCameraPosition: _initialCamera,
            onMapCreated: (controller) {
              _mapController = controller;
              _mapReady = true;
            },
            myLocationEnabled: true,
            myLocationButtonEnabled: true,
            markers: _markers,
            polylines: _polylines,
            zoomControlsEnabled: false,
            scrollGesturesEnabled: !_pickupLocked,
            rotateGesturesEnabled: !_pickupLocked,
            tiltGesturesEnabled: !_pickupLocked,
            onCameraMoveStarted: () {
              // user started moving map; cancel previous debounce
              _debounceReverse?.cancel();
            },
            onCameraIdle: () async {
              // Only auto-update pickup when NOT hard-locked and not temporarily paused by manual pick
              if (!_pickupLocked && !_userManuallyPickedPickup) {
                // read center latlng
                try {
                  final size = MediaQuery.of(context).size;
                  final ScreenCoordinate screenCenter = ScreenCoordinate(
                    x: (size.width / 2).round(),
                    y: (size.height / 2).round(),
                  );
                  final LatLng centerLatLng = await _mapController.getLatLng(
                    screenCenter,
                  );
                  // debounce reverse geocode
                  _debounceReverse?.cancel();
                  _debounceReverse = Timer(
                    const Duration(milliseconds: 500),
                    () {
                      _reverseGeocodeAndSetPickup(
                        centerLatLng,
                        updateText: true,
                      );
                    },
                  );
                } catch (e) {
                  // ignore
                }
              }
            },
          ),

          // NOTE: center pin removed (we don't show any overlay pin now)

          // Top floating controls
          Positioned(
            top: 12,
            left: 12,
            right: 12,
            child: Column(
              children: [
                // Pickup area (read-only, but tapping opens autocomplete for manual pick)
                _floatingInput(
                  icon: Icons.my_location,
                  controller: _pickupController,
                  hint: _pickupLocked
                      ? 'Pickup (confirmed)'
                      : 'Set pickup (drag map or tap to edit)',
                  onTap: () {
                    // allow user to choose pickup manually (hybrid)
                    _openAutocompleteSheet(isPickup: true);
                  },
                ),
                const SizedBox(height: 8),
                // Destination (only selectable via autocomplete)
                _floatingInput(
                  icon: Icons.location_on,
                  controller: _destinationController,
                  hint: 'Where to? (tap to search)',
                  onTap: () {
                    _openAutocompleteSheet(isPickup: false);
                  },
                ),
              ],
            ),
          ),

          // Bottom area: show fare summary when both locations are set
          Positioned(
            left: 12,
            right: 12,
            bottom: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [

                // If a driver has been found/assigned, show a driver profile card here
                if (_mockDriver != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 30,
                          backgroundColor: Colors.grey[200],
                          child: const Icon(
                            Icons.person,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _mockDriver!['name'] ?? 'Driver',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${_mockDriver!['vehicle'] ?? ''} • ${_mockDriver!['plate'] ?? ''}',
                                style: const TextStyle(color: Colors.grey),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'ETA ${_mockDriver!['eta_min'] ?? '--'} min',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          children: [
                            OutlinedButton(
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Message driver (not implemented)',
                                    ),
                                  ),
                                );
                              },
                              child: const Text('Message'),
                            ),
                            const SizedBox(height: 6),
                            ElevatedButton(
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Call driver (not implemented)',
                                    ),
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: campusGreen,
                              ),
                              child: const Text('Call'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  )
                else
                // Fare summary and confirm booking button (bottom) — shows after route/fare computed
                if (_estimatedFare > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.12),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Text(
                            'Distance: ${_distanceKm.toStringAsFixed(2)} km • ETA: ${_durationMin.toStringAsFixed(0)} min',
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Text(
                                  'Estimated fare: RM ${_estimatedFare.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: _startFindingDriver,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: campusGreen,
                              ),
                              child: const Text('Confirm'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // floating search box / display
  Widget _floatingInput({
    required IconData icon,
    required TextEditingController controller,
    required String hint,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF00BFA6)),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: controller,
                readOnly: true,
                onTap: onTap,
                decoration: InputDecoration(
                  hintText: hint,
                  border: InputBorder.none,
                ),
              ),
            ),
            const Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }

  // Show autocomplete bottom sheet for pickup or destination
  void _openAutocompleteSheet({required bool isPickup}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.35,
          maxChildSize: 0.95,
          builder: (context, sheetCtrl) {
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const SizedBox(width: 40),
                      Text(
                        isPickup ? 'Set Pickup' : 'Set Destination',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // "My Current Position" button
                  if (isPickup)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: GestureDetector(
                        onTap: () async {
                          try {
                            final position =
                                await Geolocator.getCurrentPosition(
                                  desiredAccuracy: LocationAccuracy.high,
                                );
                            final currentPos = LatLng(
                              position.latitude,
                              position.longitude,
                            );

                            // Reverse geocode to get address
                            final url =
                                'https://maps.googleapis.com/maps/api/geocode/json?latlng=${position.latitude},${position.longitude}&key=$API_KEY';
                            final resp = await http.get(Uri.parse(url));

                            if (resp.statusCode == 200) {
                              final data = json.decode(resp.body);
                              if (data['status'] == 'OK' &&
                                  data['results'].isNotEmpty) {
                                final address =
                                    data['results'][0]['formatted_address']
                                        as String;
                                _pickupController.text = address;
                                _pickupLatLng = currentPos;
                                _userPickedPickupAndLockTemporarily();

                                // Move camera
                                try {
                                  _mapController.animateCamera(
                                    CameraUpdate.newCameraPosition(
                                      CameraPosition(
                                        target: currentPos,
                                        zoom: 16,
                                      ),
                                    ),
                                  );
                                } catch (_) {}

                                // Update pickup marker
                                _markers.removeWhere(
                                  (m) => m.markerId.value == 'pickup_marker',
                                );
                                _markers.add(
                                  Marker(
                                    markerId: const MarkerId('pickup_marker'),
                                    position: currentPos,
                                    infoWindow: InfoWindow(
                                      title: 'Pickup',
                                      snippet: address,
                                    ),
                                    icon: BitmapDescriptor.defaultMarkerWithHue(
                                      BitmapDescriptor.hueAzure,
                                    ),
                                  ),
                                );
                                setState(() {});
                                Navigator.pop(context);
                              }
                            }
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Error getting location: $e'),
                              ),
                            );
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            vertical: 10,
                            horizontal: 12,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00BFA6).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(0xFF00BFA6),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: const [
                              Icon(Icons.my_location, color: Color(0xFF00BFA6)),
                              SizedBox(width: 8),
                              Text(
                                'My Current Position',
                                style: TextStyle(
                                  color: Color(0xFF00BFA6),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  Container(
                    height: 50,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey[100],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.search, color: Colors.grey),
                        const SizedBox(width: 8),
                        Expanded(
                          child: GooglePlaceAutoCompleteTextField(
                            textEditingController: isPickup
                                ? _pickupController
                                : _destinationController,
                            googleAPIKey: API_KEY,
                            debounceTime: 300,
                            countries: const ['my'],
                            isLatLngRequired:
                                false, // DISABLE plugin's center-pin behavior
                            // itemClick returns prediction - we fetch details with HTTP
                            itemClick: (prediction) async {
                              // set text (safe)
                              final controller = isPickup
                                  ? _pickupController
                                  : _destinationController;
                              controller.text = prediction.description ?? '';
                              controller.selection = TextSelection.fromPosition(
                                TextPosition(offset: controller.text.length),
                              );

                              // fetch place details lat/lng
                              final details = await _getPlaceLatLngFromPlaceId(
                                prediction.placeId!,
                              );
                              if (details != null) {
                                if (isPickup) {
                                  // hybrid: user manually selected pickup -> set and mark recent
                                  _pickupLatLng = details;
                                  _userPickedPickupAndLockTemporarily();
                                  // move camera to this pickup
                                  try {
                                    _mapController.animateCamera(
                                      CameraUpdate.newCameraPosition(
                                        CameraPosition(
                                          target: details,
                                          zoom: 16,
                                        ),
                                      ),
                                    );
                                  } catch (_) {}
                                  // update marker (preview)
                                  _markers.removeWhere(
                                    (m) => m.markerId.value == 'pickup_marker',
                                  );
                                  _markers.add(
                                    Marker(
                                      markerId: const MarkerId('pickup_marker'),
                                      position: details,
                                      infoWindow: InfoWindow(
                                        title: 'Pickup',
                                        snippet: _pickupController.text,
                                      ),
                                      icon:
                                          BitmapDescriptor.defaultMarkerWithHue(
                                            BitmapDescriptor.hueAzure,
                                          ),
                                    ),
                                  );
                                  setState(() {});
                                } else {
                                  // destination chosen
                                  // CLEAR previous destination & route BEFORE adding new
                                  _markers.removeWhere(
                                    (m) =>
                                        m.markerId.value == 'dest_marker' ||
                                        (m.infoWindow.title == 'Destination'),
                                  );
                                  _polylines.clear();
                                  _distanceKm = 0.0;
                                  _durationMin = 0.0;
                                  _estimatedFare = 0.0;

                                  _destinationLatLng = details;
                                  _markers.add(
                                    Marker(
                                      markerId: const MarkerId('dest_marker'),
                                      position: details,
                                      infoWindow: InfoWindow(
                                        title: 'Destination',
                                        snippet: _destinationController.text,
                                      ),
                                      icon:
                                          BitmapDescriptor.defaultMarkerWithHue(
                                            BitmapDescriptor.hueRed,
                                          ),
                                    ),
                                  );
                                  setState(() {});

                                  // fetch route & estimate (requires pickup)
                                  if (_pickupLatLng != null) {
                                    await _fetchRouteAndEstimate(
                                      _pickupLatLng!,
                                      _destinationLatLng!,
                                    );
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Please set pickup first',
                                        ),
                                      ),
                                    );
                                  }
                                }
                              }
                              Navigator.of(context).pop();
                            },
                            inputDecoration: const InputDecoration(
                              border: InputBorder.none,
                              hintText: 'Search place',
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                            ),
                            boxDecoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView(
                      controller: sheetCtrl,
                      children: const [SizedBox(height: 200)],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Mark that user actively picked a pickup (disables auto-update for a while)
  void _userPickedPickupAndLockTemporarily() {
    // user manually picked pickup: pause camera-based updates for a short time so reverse-geocode won't overwrite
    _userManuallyPickedPickup = true;
    _pickupLocked = false; // ensure not hard-locked yet
    _debounceReverse?.cancel();

    // after 8s allow camera-based updates again (if not confirmed)
    _debounceReverse = Timer(const Duration(seconds: 8), () {
      _userManuallyPickedPickup = false;
      setState(() {});
    });

    setState(() {});
  }
}
