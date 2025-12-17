import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'rating_dialog.dart';

class ReviewsPage extends StatefulWidget {
  const ReviewsPage({Key? key}) : super(key: key);

  @override
  State<ReviewsPage> createState() => _ReviewsPageState();
}

class _ReviewsPageState extends State<ReviewsPage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> completedTrips = [];
  Map<String, Map<String, dynamic>> driverCache = {};
  Map<String, Map<String, dynamic>> reviewCache = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadCompletedTrips();
  }

  Future<void> _loadCompletedTrips() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      // Load completed trips
      final trips = await supabase
          .from('rides')
          .select()
          .eq('rider_id', user.id)
          .eq('status', 'completed')
          .order('completed_at', ascending: false)
          .limit(50);

      // Load reviews for these trips
      final tripIds = trips.map((t) => t['id']).toList();
      if (tripIds.isNotEmpty) {
        final reviews = await supabase
            .from('reviews')
            .select()
            .eq('rider_id', user.id)
            .inFilter('ride_id', tripIds);

        for (var review in reviews) {
          reviewCache[review['ride_id']] = review;
        }
      }

      if (mounted) {
        setState(() {
          completedTrips = List<Map<String, dynamic>>.from(trips);
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading completed trips: $e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<Map<String, dynamic>?> _getDriverInfo(String driverId) async {
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
      return '${date.day}/${date.month}/${date.year}';
    } catch (_) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    const campusGreen = Color(0xFF00BFA6);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: const Text('Rate Your Trips'),
        backgroundColor: campusGreen,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : completedTrips.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.rate_review_outlined,
                          size: 64, color: Colors.grey[300]),
                      const SizedBox(height: 16),
                      Text(
                        'No completed trips yet',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Complete a trip to rate your driver',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[400],
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: completedTrips.length,
                  itemBuilder: (context, index) {
                    final trip = completedTrips[index];
                    final tripId = trip['id'] as String;
                    final driverId = trip['driver_id'] as String?;
                    final review = reviewCache[tripId];
                    final hasReview = review != null;
                    final pickup = trip['pickup_address'] as String? ?? 'Unknown';
                    final destination =
                        trip['destination_address'] as String? ?? 'Unknown';
                    final fare = trip['fare'] as num? ?? 0;
                    final date = _formatDate(trip['completed_at'] as String?);

                    return Card(
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
                            // Header with date
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  date,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (hasReview)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: campusGreen.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: campusGreen),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.star,
                                          size: 14,
                                          color: campusGreen,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${review['rating']} Stars',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: campusGreen,
                                          ),
                                        ),
                                      ],
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
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: Colors.blue,
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                    ),
                                    Container(
                                      width: 2,
                                      height: 25,
                                      color: Colors.grey[300],
                                    ),
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: Colors.red,
                                        borderRadius: BorderRadius.circular(5),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        pickup,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 25),
                                      Text(
                                        destination,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // Fare and action
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'RM${fare.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                ElevatedButton.icon(
                                  onPressed: () {
                                    if (driverId != null) {
                                      _getDriverInfo(driverId).then((driverInfo) {
                                        if (driverInfo != null && mounted) {
                                          showDialog(
                                            context: context,
                                            barrierDismissible: false,
                                            builder: (BuildContext dialogContext) {
                                              return RatingDialog(
                                                tripId: tripId,
                                                driverId: driverId,
                                                driverName:
                                                    driverInfo['full_name'] ??
                                                        'Driver',
                                                driverAvatar:
                                                    driverInfo['avatar_url'],
                                              );
                                            },
                                          ).then((rated) {
                                            if (rated == true && mounted) {
                                              _loadCompletedTrips();
                                            }
                                          });
                                        }
                                      });
                                    }
                                  },
                                  icon: Icon(
                                    hasReview ? Icons.edit : Icons.rate_review,
                                    size: 16,
                                  ),
                                  label: Text(
                                    hasReview ? 'Edit' : 'Rate',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: campusGreen,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 8,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            // Show review comment if exists
                            if (hasReview && review['comment'] != null)
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 12),
                                  Divider(color: Colors.grey[300]),
                                  const SizedBox(height: 8),
                                  Text(
                                    review['comment'] as String,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
