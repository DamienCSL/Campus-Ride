// home.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'book_trip.dart';
import 'login.dart';
import 'profile.dart';
import 'user_support_chat.dart';
import 'trip_history.dart';
import 'driver_tracking.dart';
import 'notification_service.dart';
import 'notifications_page.dart';
import 'rating_dialog.dart';
import 'notification_overlay.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

class Home extends StatefulWidget {
  const Home({Key? key}) : super(key: key);

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  final supabase = Supabase.instance.client;
  final _notificationService = NotificationService();
  Map? profile;
  Map? currentRide;
  int _unreadCount = 0;
  String? _lastRatedRideId;
  bool _isRatingOpen = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _subscribeToCurrentRide();
    _initializeNotifications();
  }

  Future<void> _initializeNotifications() async {
    await _notificationService.initialize();
    
    // Listen to unread count changes
    _notificationService.unreadCountStream.listen((count) {
      if (mounted) {
        setState(() {
          _unreadCount = count;
        });
      }
    });
    
    // Set initial count
    setState(() {
      _unreadCount = _notificationService.unreadCount;
    });
  }

  Future<void> _loadProfile() async {
    final userId = supabase.auth.currentUser!.id;
    final data = await supabase
        .from("profiles")
        .select()
        .eq("id", userId)
        .single();

    setState(() {
      profile = data;
    });
  }

  Future<void> _fetchCurrentRide() async {
    try {
      final userId = supabase.auth.currentUser!.id;
      final data = await supabase
          .from("rides")
          .select()
          .eq("rider_id", userId)
          .neq("status", "completed")
          .neq("status", "cancelled")
          .order("created_at", ascending: false)
          .limit(1);

      final List dataList = data as List;
      if (dataList.isNotEmpty) {
        setState(() {
          currentRide = Map<String, dynamic>.from(dataList.first);
        });
      } else {
        setState(() {
          currentRide = null;
        });
      }
    } catch (e) {
      debugPrint('Error fetching current ride: $e');
    }
  }

  void _setupRideStatusListener() {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    debugPrint('🔄 [User] Setting up realtime listeners for user $userId');

    // Listen for ride status changes in rides table
    supabase
        .channel('rides_status_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'rides',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'rider_id',
            value: userId,
          ),
          callback: (payload) {
            final newData = payload.newRecord;
            final status = newData['status']?.toString() ?? '';
            
            debugPrint('🚗 [Rides UPDATE] Status: $status, ID: ${newData['id']}');
            
            if (status == 'cancelled' && mounted) {
              debugPrint('❌ [User] Ride cancelled via rides table');
              // Show cancellation popup
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (ctx) => AlertDialog(
                  title: const Text('Ride Cancelled'),
                  content: const Text('Your driver has cancelled the ride.'),
                  actions: [
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        // Refresh to clear cancelled ride
                        _fetchCurrentRide();
                      },
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            }

            // Completed ride -> prompt rating
            if (status == 'completed' && mounted) {
              debugPrint('✅ [User] Ride completed via rides table');
              _handleRideCompleted(newData);
            }
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'ride_requests',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'rider_id',
            value: userId,
          ),
          callback: (payload) {
            final newData = payload.newRecord;
            final status = newData['status']?.toString() ?? '';
            
            debugPrint('📋 [Ride_requests UPDATE] Status: $status, ID: ${newData['id']}');
            
            // Also listen to ride_requests cancellations (driver cancels before accepting)
            if (status == 'cancelled' && mounted) {
              debugPrint('❌ [User] Ride cancelled via ride_requests');
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (ctx) => AlertDialog(
                  title: const Text('Ride Cancelled'),
                  content: const Text('Your driver has cancelled the ride.'),
                  actions: [
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        // Refresh to clear cancelled ride
                        _fetchCurrentRide();
                      },
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            }

            // Completed ride -> prompt rating
            if (status == 'completed' && mounted) {
              _handleRideCompleted(newData);
            }
          },
        )
        .subscribe();
  }

  void _subscribeToCurrentRide() {
    _fetchCurrentRide();
    _setupRideStatusListener();
  }

  Future<void> _handleRideCompleted(Map<String, dynamic> rideData) async {
    if (_isRatingOpen) return;
    final rideId = rideData['id']?.toString();
    if (rideId == null) return;
    if (_lastRatedRideId == rideId) return;

    _isRatingOpen = true;
    try {
      final driverId = rideData['driver_id']?.toString();
      String driverName = 'Your Driver';
      String? driverAvatar;

      if (driverId != null) {
        try {
          final profileResp = await supabase
              .from('profiles')
              .select('full_name, avatar_url')
              .eq('id', driverId)
              .maybeSingle();
          if (profileResp != null) {
            driverName = profileResp['full_name']?.toString() ?? driverName;
            driverAvatar = profileResp['avatar_url']?.toString();
          }
        } catch (_) {}
      }

      if (!mounted) return;
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => RatingDialog(
          tripId: rideId,
          driverId: driverId ?? '',
          driverName: driverName,
          driverAvatar: driverAvatar,
        ),
      );

      _lastRatedRideId = rideId;
      await _fetchCurrentRide();
    } catch (_) {}
    finally {
      _isRatingOpen = false;
    }
  }

  // Pull-to-refresh to re-fetch profile and current ride
  Future<void> _handleRefresh() async {
    try {
      await Future.wait([
        _loadProfile(),
        _fetchCurrentRide(),
      ]);
    } catch (e) {
      debugPrint('Refresh error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    const campusGreen = Color(0xFF00BFA6);

    return Scaffold(
      backgroundColor: Colors.white,
      body: NotificationOverlay(
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _handleRefresh,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Hello,", style: TextStyle(fontSize: 18)),
                        Text(
                          profile?["full_name"] ?? "Loading...",
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        // Notification bell with badge
                        Stack(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.notifications_outlined),
                              iconSize: 28,
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const NotificationsPage(),
                                  ),
                                );
                              },
                            ),
                            if (_unreadCount > 0)
                              Positioned(
                                right: 8,
                                top: 8,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  constraints: const BoxConstraints(
                                    minWidth: 18,
                                    minHeight: 18,
                                  ),
                                  decoration: const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    _unreadCount > 9 ? '9+' : _unreadCount.toString(),
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
                        ),
                        IconButton(
                          icon: const Icon(Icons.logout),
                          onPressed: () async {
                            await supabase.auth.signOut();
                            if (!mounted) return;
                            Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(builder: (_) => const Login()),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 30),

                // Book Ride Card
                GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const BookTripPage()),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: campusGreen,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: const [
                        Icon(Icons.local_taxi, size: 50, color: Colors.white),
                        SizedBox(width: 16),
                        Text(
                          "Book a Ride",
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 30),

                // Quick Actions
                const Text(
                  "Quick Actions",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 14),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _actionButton(
                      icon: Icons.history,
                      label: "Ride History",
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const TripHistoryPage()),
                        );
                      },
                    ),
                    _actionButton(
                      icon: Icons.account_circle,
                      label: "Profile",
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const ProfilePage()),
                        );
                      },
                    ),
                    _actionButton(
                      icon: Icons.support_agent,
                      label: "Support",
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const UserSupportChatPage(),
                          ),
                        );
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 30),

                // Ongoing Activities (Moved below Quick Actions)
                if (currentRide != null) ...[
                  const Text(
                    "Ongoing Activities",
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue[200]!),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Current Ride",
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue[800],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Icon(Icons.location_on,
                                          size: 18,
                                          color: Colors.blue[600]),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          currentRide?["pickup_address"] ??
                                              "",
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(Icons.location_on,
                                          size: 18,
                                          color: Colors.blue[600]),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          currentRide?[
                                                  "destination_address"] ??
                                              "",
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: Colors.grey,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: _getStatusColor(
                                    currentRide?["status"] ?? "pending"),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                (currentRide?["status"] ?? "pending")
                                    .toString()
                                    .toUpperCase(),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: () async {
                            try {
                              final ride = currentRide!;
                              final driverId =
                                  ride['driver_id'] as String?;

                              if (driverId == null) {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        const TripHistoryPage(),
                                  ),
                                );
                                return;
                              }

                              final driverResp = await supabase
                                  .from('drivers')
                                  .select()
                                  .eq('id', driverId)
                                  .single();

                              final driver =
                                  Map<String, dynamic>.from(driverResp);

                              final pickupLat =
                                  (ride['pickup_lat'] is num)
                                      ? (ride['pickup_lat'] as num).toDouble()
                                      : double.tryParse(
                                              ride['pickup_lat'].toString()) ??
                                          0.0;
                              final pickupLng =
                                  (ride['pickup_lng'] is num)
                                      ? (ride['pickup_lng'] as num).toDouble()
                                      : double.tryParse(
                                              ride['pickup_lng'].toString()) ??
                                          0.0;
                              final destLat =
                                  (ride['destination_lat'] is num)
                                      ? (ride['destination_lat'] as num)
                                          .toDouble()
                                      : double.tryParse(ride[
                                                  'destination_lat']
                                              .toString()) ??
                                          0.0;
                              final destLng =
                                  (ride['destination_lng'] is num)
                                      ? (ride['destination_lng'] as num)
                                          .toDouble()
                                      : double.tryParse(ride[
                                                  'destination_lng']
                                              .toString()) ??
                                          0.0;

                              final result = await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => DriverTrackingPage(
                                    driver: driver,
                                    pickup:
                                        LatLng(pickupLat, pickupLng),
                                    destination:
                                        LatLng(destLat, destLng),
                                    rideId: ride['id'] as String?,
                                  ),
                                ),
                              );
                              
                              // Refresh data when returning from tracking
                              if (result == true && mounted) {
                                debugPrint('🔄 [Home] Returned from tracking, refreshing data');
                                await _fetchCurrentRide();
                              }
                            } catch (e) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const TripHistoryPage(),
                                ),
                              );
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.blue[600],
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              "View Details",
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, size: 28),
          ),
          const SizedBox(height: 6),
          Text(label),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange;
      case 'arriving':
        return Colors.blue;
      case 'ongoing':
        return Colors.green;
      case 'completed':
        return Colors.grey;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }
}
