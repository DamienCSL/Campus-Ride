// lib/driver_dashboard.dart
// Driver Dashboard — Supabase Flutter v2 compatible
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import 'main.dart';
import 'login.dart';
import 'error_handler.dart';
import 'ride_chat.dart';
import 'driver_navigation.dart';
import 'notification_service.dart';
import 'notification_overlay.dart';
import 'driver_profile.dart';
import 'driver_onboarding.dart';
import 'driver_notifications.dart';
import 'driver_earnings.dart';

final supabase = Supabase.instance.client;

// Put your Google Directions & Maps API key here
const String GOOGLE_API_KEY = 'AIzaSyBdppGmzFDFPxllShF0rQQXQ-nQVQdIB-Y';

class DriverDashboard extends StatefulWidget {
  const DriverDashboard({super.key});

  @override
  State<DriverDashboard> createState() => _DriverDashboardState();
}

class _DriverDashboardState extends State<DriverDashboard>
    with TickerProviderStateMixin {
  // Color constant
  static const Color campusGreen = Color(0xFF00BFA6);
  
  String driverName = "Driver";
  bool isOnline = false;
  int _bottomNavIndex = 0; // for bottom navigation
  int _unreadNotifications = 0; // badge count

  Map<String, dynamic>? _currentRide;
  int _completedRides = 0;
  double _totalIncome = 0.0;

  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  Timer? _trackingTimer;
  RealtimeChannel? _rideChannel;

  // store last known driver position for animation
  LatLng? _lastDriverPosition;

  // Navigation tracking (moved to separate driver_navigation.dart)
  List<LatLng> _fullRoutePath = []; // complete route polyline points
  bool _isNavigating = false; // true when trip is ongoing/navigating
  double _distanceToDestination =
      double.infinity; // distance to final destination in meters
  bool _completionPromptShown = false; // guard to avoid repeated prompts

  @override
  void initState() {
    super.initState();
    loadDriverData();
    _fetchIncomeSummary();
    _fetchCurrentRide();
    _restoreActiveTrip(); // Restore navigation if app was closed during active trip
    _startTrackingDriverLocation();
    _subscribeToRideUpdates();
    
    // Initialize notification service to listen for approval/rejection notifications
    NotificationService().initialize();
    
    // Listen to unread notification count
    NotificationService().unreadCountStream.listen((count) {
      if (mounted) {
        setState(() => _unreadNotifications = count);
      }
    });

    // check for pending rides every 5 seconds while online
    Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) _checkForPendingRides();
    });
  }

  @override
  void dispose() {
    _trackingTimer?.cancel();
    if (_rideChannel != null) {
      try {
        supabase.removeChannel(_rideChannel!);
      } catch (_) {}
    }
    _mapController?.dispose();
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
    final user = supabase.auth.currentUser;
    if (user == null) return;

    // If trying to go online, check approval status and license upload first
    if (value == true) {
      try {
        final driverData = await supabase
            .from("drivers")
            .select('is_approved, is_rejected, rejection_reason, license_photo_url')
            .eq("id", user.id)
            .maybeSingle();

        if (driverData == null) {
          if (mounted) {
            _showApprovalDialog(
              'Registration Incomplete',
              'Your driver registration is incomplete. Please contact support.',
              Icons.error_outline,
              Colors.orange,
            );
          }
          return;
        }

        // Check if license is uploaded
        final licensePhotoUrl = driverData['license_photo_url'] as String?;
        if (licensePhotoUrl == null || licensePhotoUrl.isEmpty) {
          if (mounted) {
            _showApprovalDialog(
              'License Not Uploaded',
              'Please upload your driver license in onboarding before going online.',
              Icons.credit_card,
              Colors.orange,
            );
          }
          return;
        }

        final isApproved = driverData['is_approved'] == true;
        final isRejected = driverData['is_rejected'] == true;
        final rejectionReason = driverData['rejection_reason'] as String?;

        if (isRejected) {
          if (mounted) {
            _showRejectionDialog(rejectionReason);
          }
          return;
        }

        if (!isApproved) {
          if (mounted) {
            _showApprovalDialog(
              'Approval Pending',
              'Your driver registration is pending admin approval. You will be notified once approved.',
              Icons.hourglass_empty,
              Colors.orange,
            );
          }
          return;
        }

        // Driver is approved and license uploaded, proceed to go online
      } catch (e) {
        debugPrint("Failed to check driver approval status: $e");
        if (mounted) {
          ErrorHandler.showErrorSnackBar(context, 'Failed to check approval status. Please try again.');
        }
        return;
      }
    }

    // Update online status
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool("driver_online_status", value);

    try {
      await supabase
          .from("drivers")
          .update({"active": value, "is_online": value})
          .eq("id", user.id);
    } catch (e) {
      debugPrint("Failed to update driver active status: $e");
    }
    
    setState(() => isOnline = value);
  }

  void _showApprovalDialog(String title, String message, IconData icon, Color color) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: TextStyle(color: color, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showRejectionDialog(String? reason) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.cancel, color: Colors.red, size: 28),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Registration Rejected',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your driver registration has been rejected.',
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 12),
            if (reason != null) ...[
              const Text(
                'Reason:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  reason,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
              const SizedBox(height: 16),
            ],
            const Text(
              'You can upload a new license photo and resubmit your application.',
              style: TextStyle(fontSize: 14, color: Colors.black87),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pushNamed(context, '/driver_license_resubmit');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00BFA6),
            ),
            icon: const Icon(Icons.upload_file),
            label: const Text('Resubmit License'),
          ),
        ],
      ),
    );
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
        final List<Map<String, dynamic>> rides =
            List<Map<String, dynamic>>.from(resp);
        setState(() {
          _completedRides = rides.length;
          _totalIncome = rides.fold(
            0.0,
            (sum, r) => sum + ((r['fare'] as num?)?.toDouble() ?? 0.0),
          );
        });
      }
    } catch (e) {
      debugPrint('Error fetching rides: $e');
    }
  }

  // ------------------------- Distance helper -------------------------
  double _calculateDistance(LatLng from, LatLng to) {
    const double R = 6371; // Earth radius in km
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

  // ------------------------- Helper: safe cast to double -------------------------
  double _toDouble(dynamic v, {double fallback = 0.0}) {
    try {
      if (v == null) return fallback;
      return (v as num).toDouble();
    } catch (_) {
      try {
        return double.parse(v.toString());
      } catch (_) {
        return fallback;
      }
    }
  }

  // ------------------------- Animate driver marker -------------------------
  // Smooth animation by interpolating positions
  void _animateDriverMarker(LatLng from, LatLng to) {
    final steps = 12;
    final latStep = (to.latitude - from.latitude) / steps;
    final lngStep = (to.longitude - from.longitude) / steps;
    for (int i = 1; i <= steps; i++) {
      Future.delayed(Duration(milliseconds: i * 90), () {
        if (!mounted)
          return; // Check if widget is still in tree before setState

        final newPos = LatLng(
          from.latitude + latStep * i,
          from.longitude + lngStep * i,
        );
        // update marker
        setState(() {
          _markers.removeWhere((m) => m.markerId.value == 'driver_marker');
          _markers.add(
            Marker(
              markerId: const MarkerId('driver_marker'),
              position: newPos,
              infoWindow: const InfoWindow(title: 'You'),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                BitmapDescriptor.hueGreen,
              ),
            ),
          );
        });
      });
    }
  }

  // ------------------------- Start tracking -------------------------
  void _startTrackingDriverLocation() {
    // initial immediate update, then periodic
    Future.delayed(Duration.zero, () async {
      await _updateDriverLocationOnce();
    });

    _trackingTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      await _updateDriverLocationOnce();
    });
  }

  Future<void> _updateDriverLocationOnce() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      // Only track location if user is online AND we have a current ride (driver mode)
      // This prevents passengers from trying to write to driver_locations table
      if (!isOnline || _currentRide == null) {
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        debugPrint('Location permission denied.');
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      if (!mounted) return; // Widget was disposed, stop here

      // Update drivers table positions
      await supabase
          .from('drivers')
          .update({"current_lat": pos.latitude, "current_lng": pos.longitude})
          .eq("id", user.id);

      // flush any pending driver location entries saved locally
      try {
        final prefs = await SharedPreferences.getInstance();
        final pendingRaw = prefs.getString('pending_driver_locations');
        if (pendingRaw != null) {
          final List pendingList = json.decode(pendingRaw) as List;
          for (final item in pendingList) {
            try {
              await supabase.from('driver_locations').insert(item);
            } catch (e) {
              ErrorHandler.logError('flush_pending_driver_locations', e);
              // stop trying to flush further to avoid loops
              break;
            }
          }
          await prefs.remove('pending_driver_locations');
        }
      } catch (e) {
        ErrorHandler.logError('flush_pending_driver_locations', e);
      }

      // keep location history (save to DB; if RLS prevents insert, persist locally for retry)
      try {
        await supabase.from('driver_locations').insert({
          "driver_id": user.id,
          "lat": pos.latitude,
          "lng": pos.longitude,
          "recorded_at": DateTime.now().toIso8601String(),
        });
      } catch (e) {
        // Row-level security or other DB error — persist locally for retry
        ErrorHandler.logError('driver_locations insert', e);
        try {
          final prefs = await SharedPreferences.getInstance();
          final pendingRaw = prefs.getString('pending_driver_locations');
          final List pendingList = pendingRaw != null
              ? json.decode(pendingRaw) as List
              : [];
          pendingList.add({
            "driver_id": user.id,
            "lat": pos.latitude,
            "lng": pos.longitude,
            "recorded_at": DateTime.now().toIso8601String(),
          });
          await prefs.setString(
            'pending_driver_locations',
            json.encode(pendingList),
          );
        } catch (e2) {
          ErrorHandler.logError('persist_pending_driver_location', e2);
        }
      }

      if (!mounted) return; // Check again after async operations

      final newLatLng = LatLng(pos.latitude, pos.longitude);

      // ensure driver marker exists; if not, add immediately
      if (!_markers.any((m) => m.markerId.value == 'driver_marker')) {
        _markers.add(
          Marker(
            markerId: const MarkerId('driver_marker'),
            position: newLatLng,
            infoWindow: const InfoWindow(title: 'You'),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              BitmapDescriptor.hueGreen,
            ),
          ),
        );
        _lastDriverPosition = newLatLng;
        if (mounted) {
          setState(() {});
        }
      } else {
        // animate from last known position
        final prev =
            _lastDriverPosition ??
            _markers
                .firstWhere((m) => m.markerId.value == 'driver_marker')
                .position;
        _animateDriverMarker(prev, newLatLng);
        _lastDriverPosition = newLatLng;
      }

      // move camera to follow driver (small animation)
      try {
        if (_mapController != null && mounted) {
          _mapController!.animateCamera(
            CameraUpdate.newLatLngZoom(newLatLng, 15),
          );
        }
      } catch (e) {
        debugPrint('Camera animate error: $e');
      }

      // --- Update proximity to destination and auto-complete if within threshold ---
      if (_currentRide != null) {
        final status = _currentRide!['status']?.toString() ?? '';
        final destLat = _toDouble(_currentRide!['destination_lat']);
        final destLng = _toDouble(_currentRide!['destination_lng']);
        final distance = Geolocator.distanceBetween(
          newLatLng.latitude,
          newLatLng.longitude,
          destLat,
          destLng,
        );

        _distanceToDestination = distance;

        debugPrint('📍 [Proximity] status=$status dist=${distance.toStringAsFixed(1)}m');

        // Re-arm the prompt if driver moved away again (>150m)
        if (distance > 150) {
          _completionPromptShown = false;
        }

        // Auto prompt completion once within 100m for ongoing/arriving rides
        if (!_completionPromptShown && distance <= 100 &&
            (status == 'ongoing' || status == 'arriving' || status == 'accepted')) {
          _completionPromptShown = true;
          // fire and forget; dialog already guards with mounted check
          _showCompleteTripConfirmation();
        }
      } else {
        _distanceToDestination = double.infinity;
        _completionPromptShown = false;
      }

      // Navigation progress tracking moved to driver_navigation.dart

      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('Location update error: $e');
    }
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
          .neq('status', 'cancelled')
          .order('created_at', ascending: false)
          .limit(1);

      final List respList = resp as List;
      if (respList.isNotEmpty) {
        setState(() {
          _currentRide = Map<String, dynamic>.from(respList.first);
          _completionPromptShown = false;
        });
        await _updateMapMarkers();
      } else {
        setState(() => _currentRide = null);
        // clear pickup/destination markers & polylines
        _markers.removeWhere(
          (m) =>
              m.markerId.value == 'pickup' || m.markerId.value == 'destination',
        );
        _polylines.clear();
        setState(() {});
      }
    } catch (e) {
      debugPrint('Error fetching current ride: $e');
    }
  }

  // ------------------------- Realtime subscription -------------------------
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
    
    debugPrint('🔄 [Driver] Setting up realtime listeners for driver ${user.id}');

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
          callback: (payload) async {
            final newData = payload.newRecord;
            final status = newData['status']?.toString() ?? '';
            
            debugPrint('🚗 [Rides UPDATE] Status: $status, ID: ${newData['id']}');

            // Handle ride cancellation
            if (status == 'cancelled') {
              debugPrint('❌ [Driver] Ride cancelled via rides table');
              setState(() {
                _currentRide = null;
                _markers.removeWhere(
                  (m) => m.markerId.value == 'pickup' || 
                        m.markerId.value == 'destination',
                );
                _polylines.clear();
              });
              
              // Show cancellation popup
              if (mounted) {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Ride Cancelled'),
                    content: const Text('The rider has cancelled the ride.'),
                    actions: [
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );
              }
              return;
            }

            // Handle ride completion
            if (status == 'completed') {
              debugPrint('✓ [Driver] Ride completed');
              setState(() {
                _currentRide = null;
                _markers.removeWhere(
                  (m) => m.markerId.value == 'pickup' || 
                        m.markerId.value == 'destination',
                );
                _polylines.clear();
              });
              await _fetchIncomeSummary();
              return;
            }

            setState(() {
              _currentRide = Map<String, dynamic>.from(newData);
              _completionPromptShown = false;
            });

            await _updateMapMarkers();
            _fetchIncomeSummary();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'rides',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'driver_id',
            value: user.id,
          ),
          callback: (payload) async {
            final newData = payload.newRecord;

            setState(() {
              _currentRide = Map<String, dynamic>.from(newData);
              _completionPromptShown = false;
            });

            await _updateMapMarkers();
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'ride_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'assigned_driver',
            value: user.id,
          ),
          callback: (payload) async {
            final newData = payload.newRecord;
            final status = newData['status']?.toString() ?? '';
            
            debugPrint('📋 [Ride_requests UPDATE - Assigned] Status: $status');

            // Handle ride_request cancellation for assigned requests
            if (status == 'cancelled' && _currentRide != null) {
              debugPrint('❌ [Driver] Ride cancelled via assigned ride_requests');
              setState(() {
                _currentRide = null;
                _markers.removeWhere(
                  (m) => m.markerId.value == 'pickup' || 
                        m.markerId.value == 'destination',
                );
                _polylines.clear();
              });
              
              if (mounted) {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Ride Cancelled'),
                    content: const Text('The rider has cancelled the ride.'),
                    actions: [
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );
              }
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'ride_requests',
          callback: (payload) async {
            final newData = payload.newRecord;
            final status = newData['status']?.toString() ?? '';
            final rideRequestId = newData['id']?.toString() ?? '';
            
            debugPrint('📋 [Ride_requests UPDATE - ALL] Status: $status, Current Ride ID: ${_currentRide?['id']}, Update ID: $rideRequestId');

            // Also listen to ALL ride_request updates to catch cancellations of unassigned requests
            // This catches cancellations before driver has assigned themselves
            if (status == 'cancelled' && 
                _currentRide != null && 
                _currentRide!['id'] == rideRequestId) {
              debugPrint('❌ [Driver] Ride cancelled via all ride_requests (unassigned)');
              setState(() {
                _currentRide = null;
                _markers.removeWhere(
                  (m) => m.markerId.value == 'pickup' || 
                        m.markerId.value == 'destination',
                );
                _polylines.clear();
              });
              
              if (mounted) {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Ride Cancelled'),
                    content: const Text('The rider has cancelled the ride.'),
                    actions: [
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );
              }
            }
          },
        )
        .subscribe();
  }

  // ------------------------- Update map markers (and draw route) -------------------------
  Future<void> _updateMapMarkers() async {
    // remove existing pickup/destination markers (but keep driver)
    _markers.removeWhere(
      (m) => m.markerId.value == 'pickup' || m.markerId.value == 'destination',
    );
    _polylines.clear();

    if (_currentRide != null) {
      final pickup = LatLng(
        _toDouble(_currentRide!['pickup_lat']),
        _toDouble(_currentRide!['pickup_lng']),
      );
      final destination = LatLng(
        _toDouble(_currentRide!['destination_lat']),
        _toDouble(_currentRide!['destination_lng']),
      );

      _markers.addAll([
        Marker(
          markerId: const MarkerId('pickup'),
          position: pickup,
          infoWindow: InfoWindow(
            title: 'Pickup',
            snippet: _currentRide!['pickup_address']?.toString() ?? '',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
        ),
        Marker(
          markerId: const MarkerId('destination'),
          position: destination,
          infoWindow: InfoWindow(
            title: 'Destination',
            snippet: _currentRide!['destination_address']?.toString() ?? '',
          ),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        ),
      ]);

      setState(() {});

      // try to fetch driving routes from Google Directions
      try {
        // 1) Driver -> Pickup (if we have driver's last position)
        if (_lastDriverPosition != null) {
          final driverToPickup = await _fetchRoutePolyline(
            _lastDriverPosition!,
            pickup,
          );
          if (driverToPickup.isNotEmpty) {
            _polylines.add(
              Polyline(
                polylineId: const PolylineId('driver_to_pickup'),
                points: driverToPickup,
                width: 6,
                color: Colors.blue,
              ),
            );
          } else {
            // fallback straight line
            _polylines.add(
              Polyline(
                polylineId: const PolylineId('driver_to_pickup_fallback'),
                points: [_lastDriverPosition!, pickup],
                width: 4,
                color: Colors.blue,
              ),
            );
          }
        }

        // 2) Pickup -> Destination (existing behavior)
        final pickupToDest = await _fetchRoutePolyline(pickup, destination);
        if (pickupToDest.isNotEmpty) {
          _polylines.add(
            Polyline(
              polylineId: const PolylineId('route'),
              points: pickupToDest,
              width: 6,
              color: Colors.green,
            ),
          );
        } else {
          // fallback straight polyline
          _polylines.add(
            Polyline(
              polylineId: const PolylineId('route_fallback'),
              points: [pickup, destination],
              width: 4,
              color: Colors.green,
            ),
          );
        }
      } catch (e) {
        debugPrint('Route fetch error: $e');
        // fallback straight polylines
        if (_lastDriverPosition != null) {
          _polylines.add(
            Polyline(
              polylineId: const PolylineId('driver_to_pickup_fallback'),
              points: [_lastDriverPosition!, pickup],
              width: 4,
              color: Colors.blue,
            ),
          );
        }
        _polylines.add(
          Polyline(
            polylineId: const PolylineId('route_fallback'),
            points: [pickup, destination],
            width: 4,
            color: Colors.green,
          ),
        );
      }

      // Focus camera to show pickup & destination & driver (bounds)
      await Future.delayed(const Duration(milliseconds: 300));
      _moveCameraToBoundsWithPadding([
        pickup,
        destination,
        _lastDriverPosition,
      ]);
    } else {
      setState(() {});
    }
  }

  // Move camera to bounds containing points (ignoring nulls)
  Future<void> _moveCameraToBoundsWithPadding(List<LatLng?> points) async {
    final valid = points.whereType<LatLng>().toList();
    if (valid.isEmpty || _mapController == null) return;

    double minLat = valid.first.latitude;
    double maxLat = valid.first.latitude;
    double minLng = valid.first.longitude;
    double maxLng = valid.first.longitude;

    for (final p in valid) {
      minLat = min(minLat, p.latitude);
      maxLat = max(maxLat, p.latitude);
      minLng = min(minLng, p.longitude);
      maxLng = max(maxLng, p.longitude);
    }

    final bounds = LatLngBounds(
      southwest: LatLng(minLat, minLng),
      northeast: LatLng(maxLat, maxLng),
    );

    try {
      final cameraUpdate = CameraUpdate.newLatLngBounds(bounds, 80);
      await _mapController!.animateCamera(cameraUpdate);
    } catch (e) {
      // sometimes animateCamera with bounds fails if map not ready - fallback to center on pickup
      debugPrint('Bounds camera error: $e');
      final center = LatLng((minLat + maxLat) / 2, (minLng + maxLng) / 2);
      _mapController!.animateCamera(CameraUpdate.newLatLng(center));
    }
  }

  // ------------------------- Fetch turn-by-turn navigation steps -------------------------
  // Navigation logic moved to driver_navigation.dart

  // Navigation logic moved to driver_navigation.dart

  // Navigation utility methods moved to driver_navigation.dart

  /// Get status color based on ride status
  Color _getStatusColor(String? status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'ongoing':
        return Colors.blue;
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  /// Get status label based on ride status
  String _getStatusLabel(String? status) {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'ongoing':
        return 'Ongoing';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      default:
        return 'Unknown';
    }
  }

  /// Build full-page navigation view when trip is ongoing
  // Navigation view methods removed - now handled in separate driver_navigation.dart

  // ------------------------- Fetch route polyline from Google Directions -------------------------
  Future<List<LatLng>> _fetchRoutePolyline(LatLng origin, LatLng dest) async {
    if (GOOGLE_API_KEY == 'YOUR_GOOGLE_API_KEY_HERE' ||
        GOOGLE_API_KEY.isEmpty) {
      debugPrint('Google API key not set. Skipping Directions request.');
      return [];
    }

    final originStr = '${origin.latitude},${origin.longitude}';
    final destStr = '${dest.latitude},${dest.longitude}';
    final url =
        'https://maps.googleapis.com/maps/api/directions/json?origin=$originStr&destination=$destStr&mode=driving&key=$GOOGLE_API_KEY';

    final res = await http.get(Uri.parse(url));
    if (res.statusCode != 200) {
      debugPrint('Directions API returned HTTP ${res.statusCode}');
      debugPrint('Directions body: ${res.body}');
      return [];
    }

    final data = json.decode(res.body) as Map<String, dynamic>;
    final status = data['status'] as String?;
    debugPrint('Directions API status: $status');
    if (data.containsKey('error_message'))
      debugPrint('Directions error_message: ${data['error_message']}');

    if (status != 'OK') {
      // status could be ZERO_RESULTS, OVER_QUERY_LIMIT, REQUEST_DENIED, INVALID_REQUEST, etc.
      return [];
    }

    final routes = data['routes'] as List<dynamic>?;
    if (routes == null || routes.isEmpty) return [];

    final overview = routes.first['overview_polyline'];
    if (overview == null || overview['points'] == null) return [];

    final encoded = overview['points'] as String;
    final decoded = _decodePolyline(encoded);
    return decoded;
  }

  // ------------------------- Polyline decoder (Google encoded polyline) -------------------------
  // Returns list of LatLng
  List<LatLng> _decodePolyline(String encoded) {
    final List<LatLng> points = [];
    int index = 0;
    int len = encoded.length;
    int lat = 0;
    int lng = 0;

    while (index < len) {
      int b;
      int shift = 0;
      int result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      final int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      final finalLat = lat / 1E5;
      final finalLng = lng / 1E5;
      points.add(LatLng(finalLat, finalLng));
    }

    return points;
  }

  // ------------------------- Update ride status -------------------------
  Future<void> _updateRideStatus(String newStatus) async {
    if (_currentRide == null) return;

    try {
      debugPrint('📝 [Driver] Updating ride ${_currentRide!['id']} to status: $newStatus');
      await supabase
          .from('rides')
          .update({
            'status': newStatus,
            'completed_at': newStatus == 'completed'
                ? DateTime.now().toIso8601String()
                : null,
          })
          .eq('id', _currentRide!['id']);

      debugPrint('✅ [Driver] Ride status updated successfully');

      // Clear outdated polylines when progressing states
      if (newStatus == 'ongoing') {
        // remove driver->pickup route once trip starts
        _polylines.removeWhere((p) => p.polylineId.value.contains('driver_to_pickup'));
        setState(() {});
      }
      if (newStatus == 'completed' || newStatus == 'cancelled') {
        _polylines.clear();
        setState(() {});
      }

      // Send notification to rider about status change
      final riderId = _currentRide!['rider_id'];
      if (riderId != null) {
        String title = '';
        String body = '';
        
        switch (newStatus) {
          case 'accepted':
            title = '✓ Driver Accepted';
            body = 'Your driver has accepted your ride request and is heading to pick you up!';
            break;
          case 'ongoing':
            title = '🚗 Trip Started';
            body = 'Your driver is on the way. Have a safe journey!';
            break;
          case 'completed':
            title = '✓ Trip Completed';
            body = 'You have arrived at your destination. Thank you for riding with us!';
            break;
          case 'arriving':
            title = '🎯 Driver Arriving';
            body = 'Your driver is arriving at the pickup location. Get ready!';
            break;
        }
        
        if (title.isNotEmpty) {
          debugPrint('🔔 [Driver] Sending notification to rider $riderId');
          NotificationService().createNotification(
            userId: riderId,
            title: title,
            body: body,
            type: 'ride',
            data: {
              'ride_id': _currentRide!['id'].toString(),
              'status': newStatus,
            },
          );
        }
      }

      await _fetchCurrentRide();
      await _fetchIncomeSummary();
    } catch (e) {
      debugPrint('❌ [Driver] Update ride error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update ride: $e')));
      }
    }
  }

  // ------------------------- Cancel ride -------------------------
  bool _canCancelRide() {
    if (_currentRide == null) return false;
    final status = _currentRide!['status'];
    // Allow cancel before trip is started
    return status == 'pending' || status == 'assigned' || status == 'accepted' || status == 'arriving';
  }

  Future<void> _cancelRide() async {
    if (_currentRide == null) return;

    // Show confirmation dialog
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Ride?'),
        content: const Text('Are you sure you want to cancel this ride?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep Ride'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _confirmCancelRide();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Cancel Ride'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmCancelRide() async {
    if (_currentRide == null) return;

    try {
      final riderId = _currentRide!['rider_id'];
      final rideId = _currentRide!['id'];

      final now = DateTime.now().toIso8601String();
      
      await supabase
          .from('rides')
          .update({
            'status': 'cancelled',
            'cancelled_at': now,
          })
          .eq('id', rideId);

      // Also cancel the ride_request
      await supabase
          .from('ride_requests')
          .update({
            'status': 'cancelled',
            'cancelled_at': now,
          })
          .eq('id', rideId);

      // Send notification to rider
      if (riderId != null) {
        NotificationService().createNotification(
          userId: riderId,
          title: '✗ Ride Cancelled',
          body: 'Your driver has cancelled the ride. You can request a new ride anytime.',
          type: 'ride',
          data: {
            'ride_id': rideId.toString(),
            'cancelled_by': 'driver',
          },
        );
      }

      if (mounted) {
        ErrorHandler.showSuccessSnackBar(
          context,
          'Ride cancelled successfully',
        );
      }

      // Refresh current ride state
      await _fetchCurrentRide();
      
      // Force UI update
      setState(() {
        _currentRide = null;
      });
    } catch (e) {
      ErrorHandler.logError('cancel_ride', e);
      if (mounted) {
        ErrorHandler.showErrorSnackBar(context, 'Failed to cancel ride: $e');
      }
    }
  }

  // ------------------------- Check for pending rides -------------------------
  Future<void> _checkForPendingRides() async {
    if (!isOnline) return;

    final user = supabase.auth.currentUser;
    if (user == null) return;

    // Drivers should not receive rides if they already have one
    if (_currentRide != null) return;

    final resp = await supabase
        .from('ride_requests')
        .select()
        .eq('status', 'open')
        .filter('assigned_driver', 'is', null)
        .order('requested_at', ascending: true)
        .limit(1);

    final List respList = resp as List;
    if (respList.isNotEmpty) {
      setState(() {
        _currentRide = Map<String, dynamic>.from(respList.first);
      });

      _showIncomingRideDialog();
      await _updateMapMarkers();
    }
  }

  // ------------------------- Incoming ride dialog -------------------------
  void _showIncomingRideDialog() {
    if (_currentRide == null) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          insetPadding: const EdgeInsets.all(16),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header with gradient background
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFF00BFA6), Color(0xFF00897B)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            padding: const EdgeInsets.all(10),
                            child: const Icon(Icons.local_taxi, color: Colors.white, size: 24),
                          ),
                          const SizedBox(width: 12),
                          const Text(
                            "New Ride Request",
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                // Content
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Pickup Location
                      _buildLocationCard(
                        icon: Icons.location_on,
                        color: const Color(0xFF00BFA6),
                        title: "Pickup Location",
                        address: _currentRide!['pickup_address'] ?? 'Unknown',
                      ),
                      const SizedBox(height: 12),
                      // Destination Location
                      _buildLocationCard(
                        icon: Icons.place,
                        color: const Color(0xFFFF6B6B),
                        title: "Destination",
                        address: _currentRide!['destination_address'] ?? 'Unknown',
                      ),
                      const SizedBox(height: 20),
                      // Fare Card
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5F5F5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFEEEEEE), width: 1),
                        ),
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Estimated Fare",
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  "RM${_currentRide!['estimated_fare']}",
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF00BFA6),
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF00BFA6).withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              padding: const EdgeInsets.all(12),
                              child: const Icon(
                                Icons.attach_money,
                                color: Color(0xFF00BFA6),
                                size: 28,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                // Action Buttons
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  child: Row(
                    children: [
                      // Reject Button
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            setState(() => _currentRide = null);
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            side: const BorderSide(color: Color(0xFFDEDEDE), width: 2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            "Reject",
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey[700],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Accept Button
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.pop(ctx);
                            _acceptRide();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00BFA6),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 2,
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_circle, size: 20),
                              SizedBox(width: 8),
                              Text(
                                "Accept",
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ------------------------- Accept ride -------------------------
  Future<void> _acceptRide() async {
    final user = supabase.auth.currentUser;
    if (user == null || _currentRide == null) return;

    final rideRequestId = _currentRide!['id'];

    try {
      // 1️⃣ Assign driver in ride_requests
      await supabase
          .from('ride_requests')
          .update({
            'assigned_driver': user.id,
            'status': 'assigned',
            'assigned_at': DateTime.now().toIso8601String(),
          })
          .eq('id', rideRequestId);

      // 2️⃣ Create a rides record for tracking (start as accepted to satisfy constraint)
      final newRide = await supabase
          .from('rides')
          .insert({
            'rider_id': _currentRide!['rider_id'],
            'driver_id': user.id,
            'pickup_address': _currentRide!['pickup_address'],
            'pickup_lat': _currentRide!['pickup_lat'],
            'pickup_lng': _currentRide!['pickup_lng'],
            'destination_address': _currentRide!['destination_address'],
            'destination_lat': _currentRide!['destination_lat'],
            'destination_lng': _currentRide!['destination_lng'],
            'distance_km': _currentRide!['distance_km'],
            'fare': _currentRide!['estimated_fare'],
            'status': 'accepted',
            'created_at': DateTime.now().toIso8601String(),
          })
          .select()
          .maybeSingle();

      if (newRide != null) {
        setState(() => _currentRide = Map<String, dynamic>.from(newRide));
        await _updateMapMarkers();
        _fetchIncomeSummary();
        
        // Send notification to rider
        final riderId = _currentRide!['rider_id'];
        if (riderId != null) {
          NotificationService().createNotification(
            userId: riderId,
            title: 'Driver Accepted Your Ride',
            body: 'Your driver is on the way to pick you up',
            type: 'ride',
            data: {
              'ride_id': newRide['id'].toString(),
              'driver_id': user.id,
            },
          );
        }
      }
    } catch (e) {
      debugPrint('Error accepting ride: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to accept ride: $e')));
      }
    }
  }

  // ------------------------- Trip button helper -------------------------
  String _getTripButtonLabel() {
    if (_currentRide == null) return 'No Ride';
    final status = _currentRide!['status'] as String?;
    switch (status) {
      case 'pending':
      case 'assigned':
      case 'accepted':
        return 'Start Trip';
      case 'arriving':
      case 'ongoing':
        // Only show "Complete Trip" if within ~100m of destination
        if (_distanceToDestination <= 100) {
          return 'Complete Trip';
        } else {
          return 'Navigating...';
        }
      default:
        return 'No Ride';
    }
  }

  /// Check if complete trip button should be enabled
  bool _canCompleteTrip() {
    if (_currentRide == null) return false;
    final status = _currentRide!['status'] as String?;
    // Allow completion once within ~50-100m of destination
    return (status == 'ongoing' || status == 'arriving') &&
        _distanceToDestination <= 100;
  }

  void _onTripButtonPressed() {
    if (_currentRide == null) return;
    final status = _currentRide!['status'] as String?;
    switch (status) {
      case 'pending':
      case 'assigned':
      case 'accepted':
        _updateRideStatus('ongoing');
        break;
      case 'arriving':
      case 'ongoing':
        // Only allow trip completion if within 100m of destination
        if (_canCompleteTrip()) {
          _showCompleteTripConfirmation();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please reach the destination to complete trip'),
              duration: Duration(seconds: 2),
            ),
          );
        }
        break;
    }
  }

  /// Show confirmation dialog before completing the trip
  Future<void> _showCompleteTripConfirmation() async {
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
                      'Distance: ${_distanceToDestination.toStringAsFixed(0)}m from destination',
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

    if (confirmed == true && mounted) {
      await _updateRideStatus('completed');
    }
  }

  /// Restore active trip if app was closed during navigation
  /// This ensures the driver returns to navigation screen after restart
  Future<void> _restoreActiveTrip() async {
    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Check if there's an active ongoing/arriving ride
      final response = await supabase
          .from('rides')
          .select()
          .eq('driver_id', userId)
          .inFilter('status', ['ongoing', 'arriving'])
          .maybeSingle();

      if (response != null) {
        // Active ride found, restore navigation
        setState(() {
          _currentRide = response;
        });

        // Navigation now handled in separate driver_navigation.dart
        debugPrint('✅ Trip restored: ${response['id']}');
      }
    } catch (e) {
      debugPrint('Error restoring active trip: $e');
    }
  }

  // ------------------------- Logout -------------------------
  Future<void> logout() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await supabase.auth.signOut();
    if (!mounted) return;
    navigatorKey.currentState?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const Login()),
      (route) => false,
    );
  }

  // ------------------------- UI -------------------------
  @override
  Widget build(BuildContext context) {
    // Navigation now handled in separate driver_navigation.dart
    // Dashboard always shows card-based view

    // Otherwise, show normal dashboard view
    double? tripProgress;
    if (_currentRide != null && _lastDriverPosition != null) {
      final driverPos = _lastDriverPosition!;
      final pickup = LatLng(
        _toDouble(_currentRide!['pickup_lat']),
        _toDouble(_currentRide!['pickup_lng']),
      );
      final destination = LatLng(
        _toDouble(_currentRide!['destination_lat']),
        _toDouble(_currentRide!['destination_lng']),
      );

      final totalDistance = _calculateDistance(pickup, destination);
      final traveledDistance = _calculateDistance(pickup, driverPos);
      if (totalDistance > 0) {
        tripProgress = (traveledDistance / totalDistance).clamp(0.0, 1.0);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Dashboard'),
        actions: [
          // TEST BUTTON - Remove this after testing reviews
          if (_currentRide != null && _currentRide!['status'] != 'completed')
            IconButton(
              icon: const Icon(Icons.flag, color: Colors.orange),
              tooltip: 'Force Complete (Test)',
              onPressed: () async {
                await _updateRideStatus('completed');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Trip force completed - User will see rating prompt')),
                  );
                }
              },
            ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Onboarding',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DriverOnboarding()),
              );
            },
          ),
          IconButton(icon: const Icon(Icons.logout), onPressed: logout),
        ],
        backgroundColor: campusGreen,
      ),
      body: NotificationOverlay(
        child: Column(
          children: [
            Expanded(
              flex: 2,
              child: GoogleMap(
                initialCameraPosition: const CameraPosition(
                  target: LatLng(3.1390, 101.6869),
                  zoom: 12,
                ),
                markers: _markers,
                polylines: _polylines,
                onMapCreated: (controller) {
                  _mapController = controller;
                },
                myLocationEnabled: true,
                myLocationButtonEnabled: true,
              ),
            ),
            Expanded(
              flex: 3,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Welcome back, $driverName',
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
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
                                      color: isOnline ? Colors.green : Colors.red,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    isOnline
                                      ? 'Passengers can request rides.'
                                      : 'You will not receive rides.',
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ],
                            ),
                            Switch(
                              value: isOnline,
                              onChanged: toggleAvailability,
                              activeColor: campusGreen,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Current Ride:',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    if (_currentRide != null)
                      Card(
                        elevation: 2,
                        margin: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Status badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: _getStatusColor(
                                    _currentRide!['status'],
                                  ).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: _getStatusColor(
                                      _currentRide!['status'],
                                    ),
                                  ),
                                ),
                                child: Text(
                                  _getStatusLabel(_currentRide!['status']),
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: _getStatusColor(
                                      _currentRide!['status'],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Pickup and Destination
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Column(
                                    children: [
                                      Container(
                                        width: 12,
                                        height: 12,
                                        decoration: BoxDecoration(
                                          color: Colors.blue,
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        width: 2,
                                        height: 40,
                                        color: Colors.grey[300],
                                      ),
                                      Container(
                                        width: 12,
                                        height: 12,
                                        decoration: BoxDecoration(
                                          color: Colors.red,
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Pickup',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[600],
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        Text(
                                          _currentRide!['pickup_address'] ??
                                              'Unknown',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 20),
                                        Text(
                                          'Destination',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey[600],
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        Text(
                                          _currentRide!['destination_address'] ??
                                              'Unknown',
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              // Fare and trip progress
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Estimated Fare',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                      Text(
                                        'RM${(_currentRide!['fare'] ?? _currentRide!['estimated_fare'] ?? 0).toStringAsFixed(2)}',
                                        style: TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.bold,
                                          color: campusGreen,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        'Distance',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                      Text(
                                        '${(_currentRide!['distance_km'] ?? 0).toStringAsFixed(1)} km',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              // Trip progress bar
                              if (tripProgress != null) ...[
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Trip Progress',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey[600],
                                      ),
                                    ),
                                    Text(
                                      '${(tripProgress * 100).toStringAsFixed(0)}%',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: tripProgress,
                                    minHeight: 6,
                                    backgroundColor: Colors.grey[300],
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                      campusGreen,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),
                              ..._buildRideActionButtons(),
                            ],
                          ),
                        ),
                      )
                    else
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Column(
                            children: [
                              Icon(
                                Icons.local_taxi_outlined,
                                size: 48,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'No active ride',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Turn on your status to receive ride requests',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    // Enhanced Income Summary
                    Text(
                      'Income Summary:',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        // Completed Rides Card
                        Expanded(
                          child: Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Completed Rides',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '$_completedRides',
                                    style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        // Total Income Card
                        Expanded(
                          child: Card(
                            elevation: 2,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Total Income',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'RM${_totalIncome.toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: campusGreen,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _bottomNavIndex,
        onTap: (index) {
          setState(() => _bottomNavIndex = index);
          
          switch (index) {
            case 0:
              // Dashboard - already here
              break;
            case 1:
              // Notifications
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DriverNotificationsPage()),
              );
              break;
            case 2:
              // Profile
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DriverProfilePage()),
              );
              break;
            case 3:
              // Earnings
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const DriverEarningsPage()),
              );
              break;
          }
        },
        backgroundColor: Colors.white,
        type: BottomNavigationBarType.fixed,
        items: [
          BottomNavigationBarItem(
            icon: const Icon(Icons.home),
            label: 'Dashboard',
            activeIcon: Icon(Icons.home, color: campusGreen),
          ),
          BottomNavigationBarItem(
            icon: _buildNotificationBadge(),
            label: 'Notifications',
            activeIcon: _buildNotificationBadge(active: true),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.person),
            label: 'Profile',
            activeIcon: Icon(Icons.person, color: campusGreen),
          ),
          BottomNavigationBarItem(
            icon: const Icon(Icons.attach_money),
            label: 'Earnings',
            activeIcon: Icon(Icons.attach_money, color: campusGreen),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationBadge({bool active = false}) {
    return Stack(
      children: [
        Icon(
          Icons.notifications,
          color: active ? campusGreen : Colors.grey,
        ),
        if (_unreadNotifications > 0)
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(10),
              ),
              constraints: const BoxConstraints(
                minWidth: 18,
                minHeight: 18,
              ),
              child: Text(
                _unreadNotifications > 99 ? '99+' : '$_unreadNotifications',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }

  // Helper method to build location cards
  Widget _buildLocationCard({
    required IconData icon,
    required Color color,
    required String title,
    required String address,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2), width: 1.5),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(10),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  address,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Build action buttons for the ride (Open Navigation, Start Trip, Chat, Cancel)
  List<Widget> _buildRideActionButtons() {
    if (_currentRide == null) return [];
    
    final status = _currentRide!['status']?.toString() ?? '';
    
    // List to hold widgets
    final widgets = <Widget>[];
    
    // Show Open Navigation for assigned/accepted/arriving/ongoing
    if (status == 'assigned' || status == 'accepted' || status == 'arriving' || status == 'ongoing') {
      widgets.add(
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => DriverNavigationPage(ride: _currentRide!),
                  ),
                );
              },
              icon: const Icon(Icons.navigation),
              label: const Text('Open Navigation'),
              style: ElevatedButton.styleFrom(
                backgroundColor: campusGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),
      );
    }
    
    // Button layout: arriving/ongoing shows Chat left + Action right
    if (status == 'arriving' || status == 'ongoing') {
      widgets.add(
        Row(
          children: [
            // Chat button (left)
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  final currentUser = supabase.auth.currentUser;
                  final riderId = _currentRide!['rider_id']?.toString() ?? '';
                  if (currentUser != null && _currentRide != null && riderId.isNotEmpty) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RideChatPage(
                          rideId: _currentRide!['id'] ?? '',
                          myUserId: currentUser.id,
                          peerUserId: riderId,
                          peerName: 'Passenger',
                        ),
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Passenger information not available')),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.chat),
                label: const Text('Chat'),
              ),
            ),
            const SizedBox(width: 12),
            // Main action on the right (Navigating... / Complete Trip)
            Expanded(
              child: ElevatedButton(
                onPressed: _onTripButtonPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: campusGreen,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(
                  _getTripButtonLabel(),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      // Start Trip full-width (for pending/assigned/accepted)
      widgets.add(
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _onTripButtonPressed,
              style: ElevatedButton.styleFrom(
                backgroundColor: campusGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(
                _getTripButtonLabel(),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ),
      );
      
      // Secondary buttons: Chat and Cancel Ride
      widgets.add(
        Row(
          children: [
            // Chat button
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () {
                  final currentUser = supabase.auth.currentUser;
                  final riderId = _currentRide!['rider_id']?.toString() ?? '';
                  if (currentUser != null && _currentRide != null && riderId.isNotEmpty) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => RideChatPage(
                          rideId: _currentRide!['id'] ?? '',
                          myUserId: currentUser.id,
                          peerUserId: riderId,
                          peerName: 'Passenger',
                        ),
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Passenger information not available')),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                icon: const Icon(Icons.chat),
                label: const Text('Chat'),
              ),
            ),
            const SizedBox(width: 12),
            // Cancel button (only if ride not started)
            if (status != 'ongoing')
              Expanded(
                child: ElevatedButton(
                  onPressed: _canCancelRide() ? _cancelRide : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    disabledBackgroundColor: Colors.grey,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Cancel Ride'),
                ),
              ),
          ],
        ),
      );
    }
    
    return widgets;
  }
}
