// lib/driver_earnings.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DriverEarningsPage extends StatefulWidget {
  const DriverEarningsPage({Key? key}) : super(key: key);

  @override
  State<DriverEarningsPage> createState() => _DriverEarningsPageState();
}

class _DriverEarningsPageState extends State<DriverEarningsPage> {
  final supabase = Supabase.instance.client;
  
  String _selectedFilter = 'month'; // 'today', 'week', 'month', 'all'
  Map<String, dynamic> _earningsData = {
    'total': 0.0,
    'trips': 0,
    'average': 0.0,
    'daily': {},
  };
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEarningsData();
  }

  Future<void> _loadEarningsData() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      setState(() => _isLoading = true);

      // Determine date range based on filter
      DateTime startDate;
      DateTime now = DateTime.now();
      
      switch (_selectedFilter) {
        case 'today':
          startDate = DateTime(now.year, now.month, now.day);
          break;
        case 'week':
          startDate = now.subtract(Duration(days: now.weekday - 1));
          startDate = DateTime(startDate.year, startDate.month, startDate.day);
          break;
        case 'month':
          startDate = DateTime(now.year, now.month, 1);
          break;
        case 'all':
          startDate = DateTime(2000, 1, 1); // Beginning of time
          break;
        default:
          startDate = DateTime(now.year, now.month, 1);
      }

      // Fetch completed rides with earnings
      final rides = await supabase
          .from('rides')
          .select()
          .eq('driver_id', user.id)
          .eq('status', 'completed')
          .gte('completed_at', startDate.toIso8601String())
          .lte('completed_at', now.toIso8601String());

      double totalEarnings = 0.0;
      Map<String, double> dailyEarnings = {};
      Map<int, double> monthlyEarnings = {}; // For yearly view
      
      for (var ride in rides) {
        final fare = (ride['fare'] as num?)?.toDouble() ?? 0.0;
        totalEarnings += fare;

        // Parse completed_at date
        if (ride['completed_at'] != null) {
          final completedDate = DateTime.parse(ride['completed_at']);
          final dateKey = '${completedDate.year}-${completedDate.month.toString().padLeft(2, '0')}-${completedDate.day.toString().padLeft(2, '0')}';
          
          dailyEarnings.update(dateKey, (v) => v + fare, ifAbsent: () => fare);
          
          // Also track monthly for yearly view
          monthlyEarnings.update(
            completedDate.month,
            (v) => v + fare,
            ifAbsent: () => fare,
          );
        }
      }

      if (mounted) {
        setState(() {
          _earningsData = {
            'total': totalEarnings,
            'trips': rides.length,
            'average': rides.isEmpty ? 0.0 : totalEarnings / rides.length,
            'daily': dailyEarnings,
            'monthly': monthlyEarnings,
          };
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading earnings: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _getBestDay() {
    final daily = _earningsData['daily'] as Map<String, double>? ?? {};
    if (daily.isEmpty) return 'N/A';
    
    final bestEntry = daily.entries.reduce((a, b) => a.value > b.value ? a : b);
    return '${bestEntry.key} (RM${bestEntry.value.toStringAsFixed(2)})';
  }

  String _getBestMonth() {
    final monthly = _earningsData['monthly'] as Map<int, double>? ?? {};
    if (monthly.isEmpty) return 'N/A';
    
    final bestEntry = monthly.entries.reduce((a, b) => a.value > b.value ? a : b);
    final monthName = _getMonthName(bestEntry.key);
    return '$monthName (RM${bestEntry.value.toStringAsFixed(2)})';
  }

  String _getMonthName(int month) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[month - 1];
  }

  @override
  Widget build(BuildContext context) {
    const campusGreen = Color(0xFF00BFA6);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Earnings'),
        backgroundColor: campusGreen,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Filter chips
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _buildFilterChip('Today', 'today'),
                        const SizedBox(width: 8),
                        _buildFilterChip('This Week', 'week'),
                        const SizedBox(width: 8),
                        _buildFilterChip('This Month', 'month'),
                        const SizedBox(width: 8),
                        _buildFilterChip('All Time', 'all'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Total earnings card
                  Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [campusGreen, campusGreen.withOpacity(0.7)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: campusGreen.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total Earnings',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.white.withOpacity(0.8),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'RM${(_earningsData['total'] as num).toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 42,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Trips',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white.withOpacity(0.8),
                                  ),
                                ),
                                Text(
                                  '${_earningsData['trips']}',
                                  style: const TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Average/Trip',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white.withOpacity(0.8),
                                  ),
                                ),
                                Text(
                                  'RM${(_earningsData['average'] as num).toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Statistics section
                  Text(
                    'Performance Metrics',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),

                  // Best day card
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.all(12),
                            child: const Icon(
                              Icons.calendar_today,
                              color: Colors.blue,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Best Day',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _getBestDay(),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Best month card
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            padding: const EdgeInsets.all(12),
                            child: const Icon(
                              Icons.date_range,
                              color: Colors.orange,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Best Month',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _getBestMonth(),
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Daily breakdown
                  if ((_earningsData['daily'] as Map?)?.isNotEmpty ?? false) ...[
                    Text(
                      'Daily Breakdown',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    ..._buildDailyBreakdown(),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedFilter == value;
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.white : Colors.grey[700],
          fontWeight: FontWeight.w600,
        ),
      ),
      backgroundColor: isSelected ? const Color(0xFF00BFA6) : Colors.grey[200],
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() => _selectedFilter = value);
          _loadEarningsData();
        }
      },
    );
  }

  List<Widget> _buildDailyBreakdown() {
    final daily = _earningsData['daily'] as Map<String, double>? ?? {};
    final sortedEntries = daily.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value)); // Sort by earnings descending

    return sortedEntries.map((entry) {
      final date = entry.key;
      final earning = entry.value;
      
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Card(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      date,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _getDayName(date),
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
                Text(
                  'RM${earning.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF00BFA6),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }).toList();
  }

  String _getDayName(String dateStr) {
    try {
      final date = DateTime.parse(dateStr);
      const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
      return days[date.weekday - 1];
    } catch (e) {
      return '';
    }
  }
}
