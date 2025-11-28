import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class DriverTrackingPage extends StatefulWidget {
  final Map<String, dynamic> driver;
  final LatLng pickup;
  final LatLng destination;

  const DriverTrackingPage({
    Key? key,
    required this.driver,
    required this.pickup,
    required this.destination,
  }) : super(key: key);

  @override
  State<DriverTrackingPage> createState() => _DriverTrackingPageState();
}

class _DriverTrackingPageState extends State<DriverTrackingPage> {
  late GoogleMapController _mapController;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};

  LatLng? _driverPos;
  Timer? _mockMoveTimer;

  @override
  void initState() {
    super.initState();
    _driverPos = LatLng(
      widget.pickup.latitude + 0.002,
      widget.pickup.longitude + 0.002,
    );

    _startMockLiveMovement();
  }

  @override
  void dispose() {
    _mockMoveTimer?.cancel();
    super.dispose();
  }

  void _startMockLiveMovement() {
    int tick = 0;

    _mockMoveTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      tick++;

      // simulate driver moving to pickup
      double latStep = (widget.pickup.latitude - _driverPos!.latitude) / 40;
      double lngStep = (widget.pickup.longitude - _driverPos!.longitude) / 40;

      _driverPos = LatLng(
        _driverPos!.latitude + latStep,
        _driverPos!.longitude + lngStep,
      );

      _updateMarkers();

      if (!mounted) return;
      if (tick >= 40) t.cancel();
    });
  }

  void _updateMarkers() {
    _markers = {
      Marker(
        markerId: const MarkerId('pickup'),
        position: widget.pickup,
        icon:
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: const InfoWindow(title: "Pickup Location"),
      ),
      Marker(
        markerId: const MarkerId('destination'),
        position: widget.destination,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: "Destination"),
      ),
      Marker(
        markerId: const MarkerId('driver'),
        position: _driverPos!,
        icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: "Driver"),
      ),
    };

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    const campusGreen = Color(0xFF00BFA6);

    return Scaffold(
      appBar: AppBar(
        title: Text("Tracking ${widget.driver['name']}"),
        backgroundColor: campusGreen,
      ),
      body: Stack(
        children: [
          GoogleMap(
            initialCameraPosition:
                CameraPosition(target: widget.pickup, zoom: 15),
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: false,
            onMapCreated: (c) => _mapController = c,
          ),

          // driver info bottom bar
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(20)),
                boxShadow: [
                  BoxShadow(blurRadius: 6, color: Colors.black26),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.person)),
                    title: Text(widget.driver['name']),
                    subtitle: Text(
                      "${widget.driver['vehicle']} • ${widget.driver['plate']}",
                    ),
                    trailing: Text(
                      "ETA ${widget.driver['eta_min']}m",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {},
                          child: const Text("Message"),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {},
                          style: ElevatedButton.styleFrom(
                            backgroundColor: campusGreen,
                          ),
                          child: const Text("Call Driver"),
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
    );
  }
}
