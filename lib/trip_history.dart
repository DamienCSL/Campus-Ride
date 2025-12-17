import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'trip_detail.dart';
import 'rating_dialog.dart';

class TripHistoryPage extends StatefulWidget {
  const TripHistoryPage({Key? key}) : super(key: key);

  @override
  State<TripHistoryPage> createState() => _TripHistoryPageState();
}

class _TripHistoryPageState extends State<TripHistoryPage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> trips = [];
  Map<String, Map<String, dynamic>> driverCache = {}; // Cache driver info
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTripHistory();
  }

  Future<void> _loadTripHistory() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final response = await supabase
          .from('rides')
          .select()
          .eq('rider_id', user.id)
          .order('created_at', ascending: false)
          .limit(50);

      if (mounted) {
        setState(() {
          trips = List<Map<String, dynamic>>.from(response);
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading trip history: $e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<Map<String, dynamic>?> _getDriverInfo(String driverId) async {
    // Check cache first
    if (driverCache.containsKey(driverId)) {
      return driverCache[driverId];
    }

    try {
      final driver = await supabase
          .from('profiles')
          .select()
          .eq('id', driverId)
          .maybeSingle();

      if (driver != null) {
        driverCache[driverId] = driver;
      }
      return driver;
    } catch (e) {
      debugPrint('Error loading driver info: $e');
      return null;
    }
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip History'),
        backgroundColor: campusGreen,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : trips.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.history, size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text(
                        'No trips yet',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: trips.length,
                  itemBuilder: (context, index) {
                    final trip = trips[index];
                    final status = trip['status'] as String?;
                    final pickup = trip['pickup_address'] as String? ?? 'Unknown';
                    final destination =
                        trip['destination_address'] as String? ?? 'Unknown';
                    final fare = trip['fare'] as num? ?? trip['estimated_fare'] as num? ?? 0;
                    final date = _formatDate(trip['created_at'] as String?);

                    return GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                TripDetailPage(tripId: trip['id']),
                          ),
                        );
                      },
                      child: Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Header with status
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      date,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          _getStatusColor(status).withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: _getStatusColor(status),
                                      ),
                                    ),
                                    child: Text(
                                      _getStatusLabel(status),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: _getStatusColor(status),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              // Route info
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
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                      ),
                                      Container(
                                        width: 2,
                                        height: 30,
                                        color: Colors.grey[300],
                                      ),
                                      Container(
                                        width: 12,
                                        height: 12,
                                        decoration: BoxDecoration(
                                          color: Colors.red,
                                          borderRadius:
                                              BorderRadius.circular(6),
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
                                          pickup,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        const SizedBox(height: 30),
                                        Text(
                                          destination,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
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
                              const SizedBox(height: 12),
                              // Divider
                              Divider(color: Colors.grey[300]),
                              const SizedBox(height: 8),
                              // Fare
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Fare',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  Text(
                                    'RM${fare.toStringAsFixed(2)}',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              // Tap to view detail
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Tap to view details →',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[500],
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                  // Rating button for completed trips
                                  if (status == 'completed')
                                    IconButton(
                                      onPressed: () {
                                        if (trip['driver_id'] != null) {
                                          _getDriverInfo(trip['driver_id'])
                                              .then((driverInfo) {
                                            if (driverInfo != null && mounted) {
                                              showDialog(
                                                context: context,
                                                barrierDismissible: false,
                                                builder:
                                                    (BuildContext dialogContext) {
                                                  return RatingDialog(
                                                    tripId: trip['id'],
                                                    driverId:
                                                        trip['driver_id'] ?? '',
                                                    driverName:
                                                        driverInfo[
                                                            'full_name'] ??
                                                            'Driver',
                                                    driverAvatar: driverInfo[
                                                        'avatar_url'],
                                                  );
                                                },
                                              ).then((rated) {
                                                if (rated == true && mounted) {
                                                  _loadTripHistory();
                                                }
                                              });
                                            }
                                          });
                                        }
                                      },
                                      icon: const Icon(Icons.star_outline),
                                      iconSize: 20,
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
