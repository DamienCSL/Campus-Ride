// lib/admin_analytics.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';

class AdminAnalyticsPage extends StatefulWidget {
  const AdminAnalyticsPage({Key? key}) : super(key: key);

  @override
  State<AdminAnalyticsPage> createState() => _AdminAnalyticsPageState();
}

class _AdminAnalyticsPageState extends State<AdminAnalyticsPage> {
  final supabase = Supabase.instance.client;
  
  String _selectedView = 'hourly'; // hourly, daily, monthly
  bool _isLoading = true;
  
  Map<String, int> _hourlyData = {};
  Map<String, int> _dailyData = {};
  Map<String, int> _monthlyData = {};
  
  int _totalRides = 0;
  int _todayRides = 0;
  int _thisWeekRides = 0;
  int _thisMonthRides = 0;

  @override
  void initState() {
    super.initState();
    _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    setState(() => _isLoading = true);
    
    try {
      // Load all rides
      final ridesData = await supabase
          .from('rides')
          .select('created_at, status')
          .order('created_at', ascending: true);

      final rides = List<Map<String, dynamic>>.from(ridesData as List);
      
      // Process hourly data (last 24 hours)
      final now = DateTime.now();
      final hourlyMap = <String, int>{};
      for (int i = 23; i >= 0; i--) {
        final hour = now.subtract(Duration(hours: i)).hour;
        hourlyMap['${hour}h'] = 0;
      }
      
      // Process daily data (last 7 days)
      final dailyMap = <String, int>{};
      final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      for (int i = 6; i >= 0; i--) {
        final date = now.subtract(Duration(days: i));
        final weekday = weekdays[date.weekday - 1];
        dailyMap[weekday] = 0;
      }
      
      // Process monthly data (last 12 months)
      final monthlyMap = <String, int>{};
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      for (int i = 11; i >= 0; i--) {
        final date = DateTime(now.year, now.month - i, 1);
        final monthName = months[date.month - 1];
        monthlyMap[monthName] = 0;
      }
      
      // Count rides
      int totalRides = 0;
      int todayRides = 0;
      int thisWeekRides = 0;
      int thisMonthRides = 0;
      
      for (final ride in rides) {
        final createdAt = DateTime.parse(ride['created_at']);
        totalRides++;
        
        // Today
        if (createdAt.year == now.year && 
            createdAt.month == now.month && 
            createdAt.day == now.day) {
          todayRides++;
          
          // Hourly
          final hourKey = '${createdAt.hour}h';
          if (hourlyMap.containsKey(hourKey)) {
            hourlyMap[hourKey] = (hourlyMap[hourKey] ?? 0) + 1;
          }
        }
        
        // This week
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        if (createdAt.isAfter(weekStart.subtract(const Duration(days: 7)))) {
          thisWeekRides++;
          
          // Daily
          final weekday = weekdays[createdAt.weekday - 1];
          if (dailyMap.containsKey(weekday)) {
            dailyMap[weekday] = (dailyMap[weekday] ?? 0) + 1;
          }
        }
        
        // This month
        if (createdAt.year == now.year && createdAt.month == now.month) {
          thisMonthRides++;
        }
        
        // Monthly (last 12 months)
        final monthDiff = (now.year - createdAt.year) * 12 + (now.month - createdAt.month);
        if (monthDiff >= 0 && monthDiff < 12) {
          final monthName = months[createdAt.month - 1];
          if (monthlyMap.containsKey(monthName)) {
            monthlyMap[monthName] = (monthlyMap[monthName] ?? 0) + 1;
          }
        }
      }
      
      if (mounted) {
        setState(() {
          _hourlyData = hourlyMap;
          _dailyData = dailyMap;
          _monthlyData = monthlyMap;
          _totalRides = totalRides;
          _todayRides = todayRides;
          _thisWeekRides = thisWeekRides;
          _thisMonthRides = thisMonthRides;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading analytics: $e');
      setState(() => _isLoading = false);
    }
  }

  Map<String, int> _getCurrentData() {
    switch (_selectedView) {
      case 'hourly':
        return _hourlyData;
      case 'daily':
        return _dailyData;
      case 'monthly':
        return _monthlyData;
      default:
        return _hourlyData;
    }
  }

  String _getPeakPeriod() {
    final data = _getCurrentData();
    if (data.isEmpty) return 'N/A';
    
    var maxEntry = data.entries.first;
    for (final entry in data.entries) {
      if (entry.value > maxEntry.value) {
        maxEntry = entry;
      }
    }
    
    // Format hour as AM/PM if hourly view
    String formattedKey = maxEntry.key;
    if (_selectedView == 'hourly') {
      final hour = int.tryParse(maxEntry.key);
      if (hour != null) {
        final period = hour >= 12 ? 'pm' : 'am';
        final displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
        formattedKey = '$displayHour$period';
      }
    }
    
    return '$formattedKey (${maxEntry.value} rides)';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics & Reports'),
        backgroundColor: Colors.indigo,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadAnalytics,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAnalytics,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Summary Stats
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: 2,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                      childAspectRatio: 1.5,
                      children: [
                        _buildStatCard('Today', _todayRides.toString(), Colors.blue),
                        _buildStatCard('This Week', _thisWeekRides.toString(), Colors.green),
                        _buildStatCard('This Month', _thisMonthRides.toString(), Colors.orange),
                        _buildStatCard('All Time', _totalRides.toString(), Colors.purple),
                      ],
                    ),
                    
                    const SizedBox(height: 24),
                    
                    // Peak Period Card
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
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.amber[100],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(Icons.trending_up, color: Colors.amber[700], size: 28),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Peak ${_selectedView == "hourly" ? "Hour" : _selectedView == "daily" ? "Day" : "Month"}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _getPeakPeriod(),
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
                    
                    // View Toggle
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Ride Requests Over Time',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(value: 'hourly', label: Text('Hour', style: TextStyle(fontSize: 10))),
                            ButtonSegment(value: 'daily', label: Text('Day', style: TextStyle(fontSize: 10))),
                            ButtonSegment(value: 'monthly', label: Text('Month', style: TextStyle(fontSize: 10))),
                          ],
                          selected: {_selectedView},
                          onSelectionChanged: (Set<String> selection) {
                            setState(() => _selectedView = selection.first);
                          },
                        ),
                      ],
                    ),
                    
                    const SizedBox(height: 16),
                    
                    // Chart
                    Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: SizedBox(
                          height: 300,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SizedBox(
                              width: _getCurrentData().length * 40.0 < 300 
                                  ? double.infinity 
                                  : _getCurrentData().length * 40.0,
                              child: _buildChart(),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildStatCard(String title, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChart() {
    final data = _getCurrentData();
    if (data.isEmpty) {
      return Center(
        child: Text(
          'No data available',
          style: TextStyle(color: Colors.grey[600]),
        ),
      );
    }

    final entries = data.entries.toList();
    final maxY = entries.map((e) => e.value).reduce((a, b) => a > b ? a : b).toDouble();
    
    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxY > 0 ? maxY + 2 : 10,
        barTouchData: BarTouchData(
          enabled: true,
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                '${entries[groupIndex].key}\n${rod.toY.toInt()} rides',
                const TextStyle(color: Colors.white, fontSize: 12),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          show: true,
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                if (value.toInt() >= 0 && value.toInt() < entries.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      entries[value.toInt()].key,
                      style: const TextStyle(fontSize: 10),
                    ),
                  );
                }
                return const Text('');
              },
              reservedSize: 30,
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                return Text(
                  value.toInt().toString(),
                  style: const TextStyle(fontSize: 10),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 1,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: Colors.grey[300],
              strokeWidth: 1,
            );
          },
        ),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(
          entries.length,
          (index) => BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: entries[index].value.toDouble(),
                color: Colors.indigo,
                width: 16,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
