import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RatingDialog extends StatefulWidget {
  final String tripId;
  final String driverId;
  final String driverName;
  final String? driverAvatar;

  const RatingDialog({
    Key? key,
    required this.tripId,
    required this.driverId,
    required this.driverName,
    this.driverAvatar,
  }) : super(key: key);

  @override
  State<RatingDialog> createState() => _RatingDialogState();
}

class _RatingDialogState extends State<RatingDialog> {
  final supabase = Supabase.instance.client;
  int _rating = 5;
  final _commentController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitRating() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    setState(() => _isSubmitting = true);

    try {
      // Insert rating into reviews table
      await supabase.from('reviews').insert({
        'ride_id': widget.tripId,
        'rider_id': user.id,
        'driver_id': widget.driverId,
        'rating': _rating,
        'comment': _commentController.text.trim().isEmpty
            ? null
            : _commentController.text.trim(),
      });

      debugPrint('Rating submitted: $_rating stars');

      // Calculate average rating for the driver
      final allReviews = await supabase
          .from('reviews')
          .select('rating')
          .eq('driver_id', widget.driverId);

      if (allReviews.isNotEmpty) {
        final avgRating = allReviews
                .fold<double>(
                  0,
                  (sum, review) => sum + (review['rating'] as num).toDouble(),
                ) /
            allReviews.length;

        debugPrint('Average rating for driver: $avgRating');

        // Update driver's rating in the drivers table
        await supabase
            .from('drivers')
            .update({'rating': double.parse(avgRating.toStringAsFixed(2))})
            .eq('id', widget.driverId);

        debugPrint('Driver rating updated to: $avgRating');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Rating submitted successfully')),
        );
        Navigator.pop(context, true); // Return true to indicate success
      }
    } catch (e) {
      debugPrint('Error submitting rating: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const campusGreen = Color(0xFF00BFA6);
    final media = MediaQuery.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: media.size.width,
          maxHeight: media.size.height * 0.8,
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
              // Driver Avatar and Name
              Center(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.grey[300],
                      backgroundImage: widget.driverAvatar != null
                          ? NetworkImage(widget.driverAvatar!)
                          : null,
                      child: widget.driverAvatar == null
                          ? const Icon(Icons.person, size: 50)
                          : null,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Rate ${widget.driverName}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'How was your ride?',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Star Rating
              Center(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(5, (index) {
                    return GestureDetector(
                      onTap: () => setState(() => _rating = index + 1),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Icon(
                          index < _rating ? Icons.star : Icons.star_outline,
                          color: campusGreen,
                          size: 40,
                        ),
                      ),
                    );
                  }),
                ),
              ),

              const SizedBox(height: 16),

              // Rating text
              Text(
                [
                  'Poor',
                  'Fair',
                  'Good',
                  'Very Good',
                  'Excellent'
                ][_rating - 1],
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: campusGreen,
                ),
              ),

              const SizedBox(height: 24),

              // Comment TextField
              TextField(
                controller: _commentController,
                maxLines: 3,
                enabled: !_isSubmitting,
                decoration: InputDecoration(
                  hintText: 'Share your feedback (optional)',
                  hintStyle: TextStyle(color: Colors.grey[400]),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide(color: Colors.grey[300]!),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(
                      color: campusGreen,
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
              ),

              const SizedBox(height: 24),

              // Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        side: BorderSide(color: Colors.grey[300]!),
                      ),
                      child: const Text(
                        'Skip',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submitRating,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: campusGreen,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation(Colors.white),
                              ),
                            )
                          : const Text(
                              'Submit',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
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
    ));
  }
}
