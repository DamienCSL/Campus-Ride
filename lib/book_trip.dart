// lib/book_trip.dart
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_places_flutter/google_places_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

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
  final CameraPosition _initialCamera =
  const CameraPosition(target: LatLng(5.9804, 116.0735), zoom: 14);

  // controllers for text fields (read-only UI, open bottom sheet to edit)
  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _destinationController = TextEditingController();

  // state
  LatLng? _pickupLatLng;
  LatLng? _destinationLatLng;

  bool _pickupConfirmed = false; // user tapped Confirm Pickup
  bool _pickupLocked = false; // hard lock: disable auto-updates permanently after confirm
  bool _userManuallyPickedPickup = false; // temporary pause after manual pick (8s)
  bool _mapReady = false;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};

  // fare/distance/time
  double _distanceKm = 0.0;
  double _durationMin = 0.0;
  double _estimatedFare = 0.0;

  // debounce for camera idle reverse geocode
  Timer? _debounceReverse;

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
          desiredAccuracy: LocationAccuracy.best);
      final start = LatLng(pos.latitude, pos.longitude);

      // move camera after short delay (map may not be ready immediately)
      Future.delayed(const Duration(milliseconds: 300), () {
        try {
          _mapController.animateCamera(
            CameraUpdate.newCameraPosition(CameraPosition(target: start, zoom: 16)),
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
  Future<void> _reverseGeocodeAndSetPickup(LatLng latlng, {bool updateText = true}) async {
    // do not update pickup if the pickup is locked (confirmed) OR hard-locked
    if (_pickupConfirmed || _pickupLocked) return;
    try {
      final url =
          'https://maps.googleapis.com/maps/api/geocode/json?latlng=${latlng.latitude},${latlng.longitude}&key=$API_KEY';
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        if (data['status'] == 'OK' && data['results'] != null && data['results'].isNotEmpty) {
          final formatted = data['results'][0]['formatted_address'] as String;
          if (updateText) {
            _pickupController.text = formatted;
          }
          _pickupLatLng = latlng;
          // update pickup marker visually for preview (not final until confirmed)
          _markers.removeWhere((m) => m.markerId.value == 'pickup_marker');
          _markers.add(Marker(
            markerId: const MarkerId('pickup_marker'),
            position: latlng,
            infoWindow: InfoWindow(title: 'Pickup', snippet: formatted),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
          ));
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
            _estimatedFare = baseFare + (_distanceKm * perKm) + (_durationMin * perMin);
            // round to 2 decimals
            _estimatedFare = double.parse(_estimatedFare.toStringAsFixed(2));
          }

          // clear previous route and add new
          _polylines.clear();
          _polylines.add(Polyline(
            polylineId: const PolylineId('route'),
            points: points,
            width: 6,
            color: Colors.blue,
          ));

          // ensure stable destination marker at chosen lat/lng
          _markers.removeWhere((m) =>
          m.markerId.value == 'dest_marker' || (m.infoWindow.title == 'Destination'));
          _markers.add(Marker(
            markerId: const MarkerId('dest_marker'),
            position: dest,
            infoWindow: InfoWindow(title: 'Destination', snippet: _destinationController.text),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          ));

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
      await _mapController.animateCamera(CameraUpdate.newLatLngBounds(bounds, padding));
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

  // -------------- UI & Handlers --------------

  @override
  Widget build(BuildContext context) {
    const campusGreen = Color(0xFF00BFA6);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Book a Ride'),
        backgroundColor: campusGreen,
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
            scrollGesturesEnabled: !_pickupConfirmed,
            rotateGesturesEnabled: !_pickupConfirmed,
            tiltGesturesEnabled: !_pickupConfirmed,
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
                  final LatLng centerLatLng = await _mapController.getLatLng(screenCenter);
                  // debounce reverse geocode
                  _debounceReverse?.cancel();
                  _debounceReverse = Timer(const Duration(milliseconds: 500), () {
                    _reverseGeocodeAndSetPickup(centerLatLng, updateText: true);
                  });
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
                  hint: _pickupConfirmed ? 'Pickup (confirmed)' : 'Set pickup (drag map or tap to edit)',
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

          // Bottom area: either show Confirm Pickup (when destination chosen) OR fare summary
          Positioned(
            left: 12,
            right: 12,
            bottom: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // If destination selected and pickup not yet confirmed -> show Confirm Pickup button (option B)
                if (_destinationLatLng != null && !_pickupConfirmed)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8)],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Set pickup to: ${_pickupController.text}',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: campusGreen),
                          onPressed: () {
                            // Confirm pickup: lock map and finalize pickup marker
                            if (_pickupLatLng == null) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Pickup not set yet')),
                              );
                              return;
                            }

                            // hard-lock pickup: no more auto updates ever
                            _pickupLocked = true;
                            _pickupConfirmed = true;
                            _userManuallyPickedPickup = false;

                            // finalize marker (ensure single pickup marker)
                            _markers.removeWhere((m) => m.markerId.value == 'pickup_marker');
                            _markers.add(Marker(
                              markerId: const MarkerId('pickup_marker'),
                              position: _pickupLatLng!,
                              infoWindow: InfoWindow(title: 'Pickup', snippet: _pickupController.text),
                              icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
                            ));
                            // lock gesture handled by map params (scrollGesturesEnabled uses _pickupConfirmed)
                            setState(() {});
                          },
                          child: const Text('Confirm Pickup'),
                        ),
                      ],
                    ),
                  ),

                // Fare summary and confirm booking button (bottom) — shows after route/fare computed
                if (_estimatedFare > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 12)],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Distance: ${_distanceKm.toStringAsFixed(2)} km • ETA: ${_durationMin.toStringAsFixed(0)} min'),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Estimated fare: RM ${_estimatedFare.toStringAsFixed(2)}',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                              ),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                // mock booking confirm action
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Booking confirmed (mock)')),
                                );
                              },
                              style: ElevatedButton.styleFrom(backgroundColor: campusGreen),
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
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8)],
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
                            textEditingController: isPickup ? _pickupController : _destinationController,
                            googleAPIKey: API_KEY,
                            debounceTime: 300,
                            countries: const ['my'],
                            isLatLngRequired: false, // DISABLE plugin's center-pin behavior

                            // itemClick returns prediction - we fetch details with HTTP
                            itemClick: (prediction) async {
                              // set text (safe)
                              final controller = isPickup ? _pickupController : _destinationController;
                              controller.text = prediction.description ?? '';
                              controller.selection = TextSelection.fromPosition(
                                  TextPosition(offset: controller.text.length));

                              // fetch place details lat/lng
                              final details = await _getPlaceLatLngFromPlaceId(prediction.placeId!);
                              if (details != null) {
                                if (isPickup) {
                                  // hybrid: user manually selected pickup -> set and mark recent
                                  _pickupLatLng = details;
                                  _userPickedPickupAndLockTemporarily();
                                  // move camera to this pickup
                                  try {
                                    _mapController.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(target: details, zoom: 16)));
                                  } catch (_) {}
                                  // update marker (preview)
                                  _markers.removeWhere((m) => m.markerId.value == 'pickup_marker');
                                  _markers.add(Marker(
                                    markerId: const MarkerId('pickup_marker'),
                                    position: details,
                                    infoWindow: InfoWindow(title: 'Pickup', snippet: _pickupController.text),
                                    icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
                                  ));
                                  setState(() {});
                                } else {
                                  // destination chosen
                                  // CLEAR previous destination & route BEFORE adding new
                                  _markers.removeWhere((m) =>
                                  m.markerId.value == 'dest_marker' || (m.infoWindow.title == 'Destination'));
                                  _polylines.clear();
                                  _distanceKm = 0.0;
                                  _durationMin = 0.0;
                                  _estimatedFare = 0.0;

                                  _destinationLatLng = details;
                                  _markers.add(Marker(
                                    markerId: const MarkerId('dest_marker'),
                                    position: details,
                                    infoWindow: InfoWindow(title: 'Destination', snippet: _destinationController.text),
                                    icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
                                  ));
                                  setState(() {});

                                  // fetch route & estimate (requires pickup)
                                  if (_pickupLatLng != null) {
                                    await _fetchRouteAndEstimate(_pickupLatLng!, _destinationLatLng!);
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Please set pickup first')),
                                    );
                                  }
                                }
                              }
                              Navigator.of(context).pop();
                            },
                            inputDecoration: const InputDecoration(
                              border: InputBorder.none,
                              hintText: 'Search place',
                              contentPadding: EdgeInsets.symmetric(horizontal: 8),
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
                  Expanded(child: ListView(controller: sheetCtrl, children: const [SizedBox(height: 200)])),
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
    _pickupConfirmed = false; // still not locked until user taps Confirm Pickup
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
