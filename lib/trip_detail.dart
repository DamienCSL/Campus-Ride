import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'ride_chat.dart';
import 'rating_dialog.dart';

class TripDetailPage extends StatefulWidget {
  final String tripId;

  const TripDetailPage({Key? key, required this.tripId}) : super(key: key);

  @override
  State<TripDetailPage> createState() => _TripDetailPageState();
}

class _TripDetailPageState extends State<TripDetailPage> {
  final supabase = Supabase.instance.client;
  Map<String, dynamic>? trip;
  Map<String, dynamic>? driver;
  Map<String, dynamic>? driverVehicle;
  Map<String, dynamic>? review;
  bool _loading = true;
  RealtimeChannel? _rideSubscription;

  @override
  void initState() {
    super.initState();
    _loadTripDetails();
    _listenForRideUpdates();
  }

  @override
  void dispose() {
    if (_rideSubscription != null) {
      _rideSubscription!.unsubscribe();
    }
    super.dispose();
  }

  Future<void> _loadTripDetails() async {
    try {
      final user = supabase.auth.currentUser;

      // Load trip details
      final tripData = await supabase
          .from('rides')
          .select()
          .eq('id', widget.tripId)
          .single();

      if (!mounted) return;

      // Load driver details if assigned
      if (tripData['driver_id'] != null) {
        final driverData = await supabase
            .from('profiles')
            .select()
            .eq('id', tripData['driver_id'])
            .maybeSingle();

        final vehicleData = await supabase
            .from('vehicles')
            .select()
            .eq('driver_id', tripData['driver_id'])
            .maybeSingle();

        // Load review if trip is completed and user is the rider
        Map<String, dynamic>? reviewData;
        if (tripData['status'] == 'completed' && user != null) {
          reviewData = await supabase
              .from('reviews')
              .select()
              .eq('ride_id', widget.tripId)
              .eq('rider_id', user.id)
              .maybeSingle();
        }

        if (mounted) {
          setState(() {
            trip = tripData;
            driver = driverData;
            driverVehicle = vehicleData;
            review = reviewData;
            _loading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            trip = tripData;
            _loading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('Error loading trip details: $e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  /// Listen for ride updates in real-time
  void _listenForRideUpdates() {
    _rideSubscription = supabase
        .channel('rides:${widget.tripId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'rides',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.tripId,
          ),
          callback: (payload) {
            if (mounted) {
              // Refresh trip details when ride status changes
              _loadTripDetails();
            }
          },
        )
        .subscribe();
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'Unknown';
    try {
      final date = DateTime.parse(dateStr);
      return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateStr;
    }
  }

  String _getStatusLabel(String? status) {
    switch (status) {
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      case 'ongoing':
        return 'Ongoing';
      case 'pending':
        return 'Pending';
      default:
        return status ?? 'Unknown';
    }
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      case 'ongoing':
        return Colors.orange;
      case 'pending':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    const campusGreen = Color(0xFF00BFA6);

    if (_loading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Trip Details'),
          backgroundColor: campusGreen,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (trip == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Trip Details'),
          backgroundColor: campusGreen,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: const Center(
          child: Text('Trip not found'),
        ),
      );
    }

    final status = trip!['status'] as String?;
    final pickup = trip!['pickup_address'] as String? ?? 'Unknown';
    final destination = trip!['destination_address'] as String? ?? 'Unknown';
    final fare = trip!['fare'] as num? ?? trip!['estimated_fare'] as num? ?? 0;
    final date = _formatDate(trip!['created_at'] as String?);
    final duration = trip!['duration'] as String? ?? 'N/A';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip Details'),
        backgroundColor: campusGreen,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Trip Status Card
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Trip Status',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: _getStatusColor(status).withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _getStatusColor(status),
                            ),
                          ),
                          child: Text(
                            _getStatusLabel(status),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: _getStatusColor(status),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      date,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Route Card
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Route',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          children: [
                            Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: Colors.blue,
                                borderRadius: BorderRadius.circular(7),
                              ),
                            ),
                            Container(
                              width: 2,
                              height: 50,
                              color: Colors.grey[300],
                            ),
                            Container(
                              width: 14,
                              height: 14,
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(7),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Pickup',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                              Text(
                                pickup,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 50),
                              const Text(
                                'Destination',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                              Text(
                                destination,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Trip Summary Card
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Trip Summary',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildSummaryRow('Trip ID', widget.tripId),
                    const SizedBox(height: 12),
                    _buildSummaryRow('Fare', 'RM${fare.toStringAsFixed(2)}',
                        isBold: true),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Driver Info Card (if assigned)
            if (driver != null)
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Driver Information',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          CircleAvatar(
                            radius: 40,
                            backgroundColor: Colors.grey[300],
                            backgroundImage: driver!['avatar_url'] != null
                                ? NetworkImage(driver!['avatar_url'] as String)
                                : null,
                            child: driver!['avatar_url'] == null
                                ? const Icon(Icons.person, size: 40)
                                : null,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  driver!['full_name'] as String? ?? 'Unknown',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                if (driverVehicle != null)
                                  Text(
                                    '${driverVehicle!['model'] ?? 'N/A'} • ${driverVehicle!['plate_number'] ?? 'N/A'}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 16),
            // Payment Details Card
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Payment Details',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildPaymentRow('Subtotal', 'RM${fare.toStringAsFixed(2)}'),
                    const SizedBox(height: 8),
                    _buildPaymentRow('Service Fee', 'RM0.00'),
                    const SizedBox(height: 12),
                    Divider(color: Colors.grey[300]),
                    const SizedBox(height: 12),
                    _buildPaymentRow(
                      'Total',
                      'RM${fare.toStringAsFixed(2)}',
                      isTotal: true,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Rating Button (for completed trips)
            if (trip!['status'] == 'completed' && trip!['driver_id'] != null)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    // Load driver data if not already loaded
                    if (driver == null) {
                      try {
                        final profileData = await supabase
                            .from('profiles')
                            .select()
                            .eq('id', trip!['driver_id'])
                            .maybeSingle();
                        if (!mounted) return;
                        if (profileData == null) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Could not load driver data')),
                          );
                          return;
                        }
                        setState(() => driver = profileData);
                      } catch (e) {
                        debugPrint('Error loading driver data: $e');
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Error: $e')),
                          );
                        }
                        return;
                      }
                    }
                    
                    if (!mounted) return;
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (BuildContext dialogContext) {
                        return RatingDialog(
                          tripId: widget.tripId,
                          driverId: trip!['driver_id'] ?? '',
                          driverName: driver!['full_name'] ?? 'Driver',
                          driverAvatar: driver!['avatar_url'],
                        );
                      },
                    ).then((rated) {
                      if (rated == true && mounted) {
                        // Refresh trip details after rating
                        _loadTripDetails();
                      }
                    });
                  },
                  icon: Icon(review != null ? Icons.star : Icons.star_outline),
                  label: Text(review != null ? 'Update Rating' : 'Rate Driver'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00BFA6),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            // Review Display Card (for completed trips with review)
            if (trip!['status'] == 'completed' && review != null)
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Your Review',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Star rating display
                      Row(
                        children: [
                          Flexible(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: List.generate(
                                5,
                                (index) => Icon(
                                  index < (review!['rating'] as int)
                                      ? Icons.star
                                      : Icons.star_outline,
                                  color: const Color(0xFF00BFA6),
                                  size: 20,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${review!['rating']} Stars',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      // Review comment if exists
                      if (review!['comment'] != null &&
                          (review!['comment'] as String).isNotEmpty)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Your Comment',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              review!['comment'] as String,
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 12),
                      // Review date
                      Text(
                        'Reviewed on ${_formatDate(review!['created_at'] as String?)}',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 12),
            // Action buttons (Chat and Cancel)
            if (driver != null && trip!['status'] != 'completed' && trip!['status'] != 'cancelled')
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final currentUser = supabase.auth.currentUser;
                    final driverId = driver!['id']?.toString() ?? '';
                    if (currentUser != null && driverId.isNotEmpty) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => RideChatPage(
                            rideId: widget.tripId,
                            myUserId: currentUser.id,
                            peerUserId: driverId,
                            peerName: driver!['full_name'] ?? 'Driver',
                          ),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Driver information not available')),
                      );
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00BFA6),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Chat with Driver', style: TextStyle(color: Colors.white, fontSize: 16)),
                ),
              ),
            const SizedBox(height: 12),
            // Cancel button (only if trip not started)
            if (trip!['status'] != 'ongoing' && trip!['status'] != 'completed')
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _canCancelTrip() ? _cancelTrip : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    disabledBackgroundColor: Colors.grey,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text('Cancel Trip', style: TextStyle(color: Colors.white, fontSize: 16)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  bool _canCancelTrip() {
    if (trip == null) return false;
    final status = trip!['status'];
    // Can only cancel if status is pending or arriving (not ongoing or completed)
    return status == 'pending' || status == 'arriving';
  }

  Future<void> _cancelTrip() async {
    if (trip == null) return;

    // Show confirmation dialog
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Trip?'),
        content: const Text('Are you sure you want to cancel this trip?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Keep Trip'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _confirmCancelTrip();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Cancel Trip'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmCancelTrip() async {
    if (trip == null) return;

    try {
      await supabase
          .from('rides')
          .update({'status': 'cancelled'})
          .eq('id', trip!['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Trip cancelled successfully')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to cancel trip: $e')),
        );
      }
    }
  }

  Widget _buildSummaryRow(String label, String value, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            color: Colors.grey[600],
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentRow(String label, String value, {bool isTotal = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            color: isTotal ? Colors.black : Colors.grey[600],
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            color: isTotal ? const Color(0xFF00BFA6) : Colors.black,
          ),
        ),
      ],
    );
  }
}
