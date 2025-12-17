// lib/admin_driver_approval.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'error_handler.dart';
import 'notification_service.dart';

class AdminDriverApprovalPage extends StatefulWidget {
  const AdminDriverApprovalPage({Key? key}) : super(key: key);

  @override
  State<AdminDriverApprovalPage> createState() => _AdminDriverApprovalPageState();
}

class _AdminDriverApprovalPageState extends State<AdminDriverApprovalPage> {
  final supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _pendingDrivers = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPendingDrivers();
  }

  Future<void> _loadPendingDrivers() async {
    setState(() => _isLoading = true);
    
    try {
      debugPrint('🔄 [admin_driver_approval] Loading pending drivers...');
      debugPrint('   Query: SELECT * FROM drivers WHERE is_approved = false AND is_rejected = false');
      
      // Get drivers with pending approval
      final driversData = await supabase
          .from('drivers')
          .select('*, profiles!drivers_id_fkey(full_name, phone)')
          .eq('is_approved', false)
          .eq('is_rejected', false)
          .order('created_at', ascending: false);

      debugPrint('✅ [admin_driver_approval] Found ${(driversData as List).length} pending drivers');
      debugPrint('   Data: $driversData');
      
      // Also check total driver count for comparison
      final allDrivers = await supabase
          .from('drivers')
          .select('id, is_approved, is_rejected, created_at');
      debugPrint('📊 [admin_driver_approval] Total drivers in database: ${(allDrivers as List).length}');
      for (var d in allDrivers) {
        debugPrint('   - Driver ${d['id']}: is_approved=${d['is_approved']}, is_rejected=${d['is_rejected']}');
      }

      if (mounted) {
        setState(() {
          _pendingDrivers = List<Map<String, dynamic>>.from(driversData);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ [admin_driver_approval] Error loading pending drivers: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ErrorHandler.showErrorSnackBar(context, 'Failed to load drivers: $e');
      }
    }
  }

  Future<void> _approveDriver(String driverId, String driverName) async {
    try {
      await supabase
          .from('drivers')
          .update({
            'is_approved': true,
            'approved_at': DateTime.now().toIso8601String(),
          })
          .eq('id', driverId);

      // Send notification to driver
      NotificationService().createNotification(
        userId: driverId,
        title: 'Registration Approved',
        body: 'Congratulations! Your driver registration has been approved. You can now start accepting rides.',
        type: 'system',
        data: {'approved': 'true'},
      );

      if (mounted) {
        ErrorHandler.showSuccessSnackBar(
          context,
          'Driver $driverName approved successfully',
        );
      }
      
      await _loadPendingDrivers();
    } catch (e) {
      debugPrint('Error approving driver: $e');
      if (mounted) {
        ErrorHandler.showErrorSnackBar(context, 'Failed to approve driver: $e');
      }
    }
  }

  Future<void> _rejectDriver(String driverId, String driverName, String reason) async {
    try {
      await supabase
          .from('drivers')
          .update({
            'is_rejected': true,
            'rejection_reason': reason,
            'rejected_at': DateTime.now().toIso8601String(),
          })
          .eq('id', driverId);

      // Send notification to driver
      NotificationService().createNotification(
        userId: driverId,
        title: 'Registration Rejected',
        body: 'Your driver registration has been rejected. Reason: $reason',
        type: 'system',
        data: {'rejected': 'true', 'reason': reason},
      );

      if (mounted) {
        ErrorHandler.showSuccessSnackBar(
          context,
          'Driver $driverName rejected',
        );
      }
      
      await _loadPendingDrivers();
    } catch (e) {
      debugPrint('Error rejecting driver: $e');
      if (mounted) {
        ErrorHandler.showErrorSnackBar(context, 'Failed to reject driver: $e');
      }
    }
  }

  void _showDriverDetails(Map<String, dynamic> driver) {
    final profile = driver['profiles'] as Map<String, dynamic>?;
    final licensePhotoUrl = driver['license_photo_url'] as String?;
    
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.person, size: 32, color: Color(0xFF6C63FF)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        profile?['full_name'] ?? 'Unknown',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const Divider(height: 32),
                
                _buildDetailRow('Phone', profile?['phone'] ?? 'N/A'),
                _buildDetailRow('License Number', driver['license_number'] ?? 'N/A'),
                _buildDetailRow('Vehicle ID', driver['vehicle_id']?.toString() ?? 'N/A'),
                _buildDetailRow('Registered', _formatDate(driver['created_at'])),
                
                const SizedBox(height: 16),
                
                // License Photo Section
                if (licensePhotoUrl != null) ...[
                  const Text(
                    'Driver License Photo:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Color(0xFF6C63FF),
                    ),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () => _showFullImage(ctx, licensePhotoUrl),
                    child: Container(
                      width: double.infinity,
                      height: 300,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300, width: 2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          licensePhotoUrl,
                          fit: BoxFit.contain,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return Center(
                              child: CircularProgressIndicator(
                                value: progress.expectedTotalBytes != null
                                    ? progress.cumulativeBytesLoaded / progress.expectedTotalBytes!
                                    : null,
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.broken_image, size: 48, color: Colors.grey),
                                  SizedBox(height: 8),
                                  Text('Failed to load image'),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tap image to view fullscreen',
                    style: TextStyle(fontSize: 12, color: Colors.grey, fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 16),
                ] else ...[
                  const Text(
                    'No license photo uploaded',
                    style: TextStyle(color: Colors.orange, fontStyle: FontStyle.italic),
                  ),
                  const SizedBox(height: 16),
                ],
                
                const SizedBox(height: 8),
                
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showRejectDialog(driver['id'], profile?['full_name'] ?? 'Unknown');
                        },
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                          foregroundColor: Colors.red,
                        ),
                        icon: const Icon(Icons.cancel),
                        label: const Text('Reject'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {
                          Navigator.pop(ctx);
                          _approveDriver(driver['id'], profile?['full_name'] ?? 'Unknown');
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                        ),
                        icon: const Icon(Icons.check_circle),
                        label: const Text('Approve'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showFullImage(BuildContext dialogContext, String imageUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Center(
              child: InteractiveViewer(
                maxScale: 5.0,
                minScale: 0.5,
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showRejectDialog(String driverId, String driverName) {
    final reasonController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Driver'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Rejecting: $driverName'),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Rejection Reason',
                hintText: 'Enter reason for rejection',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (reasonController.text.trim().isEmpty) {
                ErrorHandler.showErrorSnackBar(ctx, 'Please enter a rejection reason');
                return;
              }
              Navigator.pop(ctx);
              _rejectDriver(driverId, driverName, reasonController.text.trim());
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey[700],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'N/A';
    try {
      final dt = DateTime.parse(date.toString());
      return '${dt.day}/${dt.month}/${dt.year}';
    } catch (e) {
      return 'N/A';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Approvals'),
        backgroundColor: const Color(0xFF6C63FF),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadPendingDrivers,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _pendingDrivers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'No pending driver approvals',
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadPendingDrivers,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _pendingDrivers.length,
                    itemBuilder: (context, index) {
                      final driver = _pendingDrivers[index];
                      final profile = driver['profiles'] as Map<String, dynamic>?;
                      final driverName = profile?['full_name'] ?? 'Unknown Driver';
                      
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: InkWell(
                          onTap: () => _showDriverDetails(driver),
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: Colors.grey[300],
                                      child: const Icon(Icons.person),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            driverName,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          Text(
                                            profile?['phone'] ?? 'No phone',
                                            style: TextStyle(
                                              fontSize: 13,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.orange[100],
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Text(
                                        'PENDING',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.orange,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Icon(Icons.phone, size: 16, color: Colors.grey[600]),
                                    const SizedBox(width: 8),
                                    Text(
                                      profile?['phone'] ?? 'No phone',
                                      style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                                    ),
                                    const SizedBox(width: 16),
                                    Icon(Icons.badge, size: 16, color: Colors.grey[600]),
                                    const SizedBox(width: 8),
                                    Text(
                                      driver['license_number'] ?? 'No license',
                                      style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: () => _showRejectDialog(
                                          driver['id'],
                                          driverName,
                                        ),
                                        style: OutlinedButton.styleFrom(
                                          side: const BorderSide(color: Colors.red),
                                          foregroundColor: Colors.red,
                                        ),
                                        icon: const Icon(Icons.cancel, size: 18),
                                        label: const Text('Reject'),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: () => _approveDriver(
                                          driver['id'],
                                          driverName,
                                        ),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.green,
                                        ),
                                        icon: const Icon(Icons.check_circle, size: 18),
                                        label: const Text('Approve'),
                                      ),
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
                ),
    );
  }
}
