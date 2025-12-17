// lib/driver_onboarding.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'dart:async';
import 'package:image_picker/image_picker.dart';
import 'error_handler.dart';
import 'notification_service.dart';

class DriverOnboarding extends StatefulWidget {
  const DriverOnboarding({Key? key}) : super(key: key);

  @override
  State<DriverOnboarding> createState() => _DriverOnboardingState();
}

class _DriverOnboardingState extends State<DriverOnboarding> {
  final supabase = Supabase.instance.client;
  File? _licensePhoto;
  bool _isUploading = false;
  Timer? _approvalCheckTimer;

  // Checklist items
  final List<Map<String, dynamic>> _checklistItems = [
    {'title': 'Upload Driver License', 'description': 'Required for verification', 'completed': false, 'id': 'license'},
    {'title': 'Review Profile', 'description': 'Ensure your information is correct', 'completed': false, 'id': 'profile'},
    {'title': 'Wait for Admin Approval', 'description': 'Admin will review and approve your registration', 'completed': false, 'id': 'approval'},
  ];

  @override
  void initState() {
    super.initState();
    _checkCompletionStatus();
    
    // Initialize notification service to listen for approval/rejection notifications
    NotificationService().initialize();
    
    // Check approval status every 3 seconds
    _approvalCheckTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      _checkApprovalStatus();
    });
  }

  @override
  void dispose() {
    _approvalCheckTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkApprovalStatus() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final driverData = await supabase
          .from('drivers')
          .select('is_approved')
          .eq('id', user.id)
          .maybeSingle();

      if (driverData != null && mounted) {
        final isApproved = driverData['is_approved'] as bool?;
        final wasApproved = _checklistItems[2]['completed'] as bool;
        
        if (isApproved == true && !wasApproved) {
          setState(() {
            _checklistItems[2]['completed'] = true;
          });
        }
      }
    } catch (e) {
      debugPrint('Error checking approval status: $e');
    }
  }

  Future<void> _checkCompletionStatus() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final driverData = await supabase
          .from('drivers')
          .select('license_photo_url, is_approved')
          .eq('id', user.id)
          .maybeSingle();

      if (driverData != null && mounted) {
        setState(() {
          _checklistItems[0]['completed'] = driverData['license_photo_url'] != null;
          _checklistItems[1]['completed'] = true; // Profile auto-completed on registration
          _checklistItems[2]['completed'] = driverData['is_approved'] == true;
        });
      }
    } catch (e) {
      debugPrint('Error checking completion status: $e');
    }
  }

  Future<void> _pickLicense() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1080,
      imageQuality: 85,
    );

    if (picked != null) {
      setState(() => _licensePhoto = File(picked.path));
    }
  }

  Future<void> _uploadLicense() async {
    if (_licensePhoto == null) {
      ErrorHandler.showErrorSnackBar(context, 'Please select a license photo');
      return;
    }

    setState(() => _isUploading = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      final path = '${user.id}/${DateTime.now().millisecondsSinceEpoch}.jpg';
      await supabase.storage
          .from('driver_licenses')
          .upload(
            path,
            _licensePhoto!,
            fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
          );

      final url = supabase.storage.from('driver_licenses').getPublicUrl(path);

      await supabase
          .from('drivers')
          .update({'license_photo_url': url})
          .eq('id', user.id);

      if (!mounted) return;

      setState(() {
        _checklistItems[0]['completed'] = true;
        _licensePhoto = null;
      });

      ErrorHandler.showSuccessSnackBar(context, 'License uploaded successfully!');
    } catch (e) {
      if (!mounted) return;
      ErrorHandler.logError('driver_onboarding', e);
      ErrorHandler.showErrorSnackBar(context, 'Failed to upload license: $e');
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const campusGreen = Color(0xFF00BFA6);
    final allCompleted = _checklistItems.every((item) => item['completed']);

    return WillPopScope(
      onWillPop: () async {
        if (allCompleted) {
          return true;
        }
        ErrorHandler.showErrorSnackBar(
          context,
          'Please complete the onboarding steps before continuing',
        );
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Welcome to CampusRide!'),
          backgroundColor: campusGreen,
          automaticallyImplyLeading: allCompleted,
          actions: [
            if (!allCompleted)
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
                tooltip: 'Exit onboarding',
              ),
          ],
        ),
        body: _isUploading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Progress Card
                    Card(
                      color: Colors.blue.shade50,
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Getting Started',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Complete these steps to start receiving ride requests:',
                              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Checklist
                    ..._checklistItems.asMap().entries.map((entry) {
                      final index = entry.key;
                      final item = entry.value;
                      final completed = item['completed'] as bool;

                      return Column(
                        children: [
                          // Checklist Item
                          Card(
                            elevation: 1,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: completed ? campusGreen : Colors.grey.shade300,
                                width: 2,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Container(
                                        width: 32,
                                        height: 32,
                                        decoration: BoxDecoration(
                                          color: completed ? campusGreen : Colors.grey.shade300,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Center(
                                          child: Text(
                                            completed ? '✓' : '${index + 1}',
                                            style: TextStyle(
                                              color: completed ? Colors.white : Colors.grey,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 16,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item['title'],
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              item['description'],
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[600],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),

                                  // License upload section
                                  if (item['id'] == 'license' && !completed) ...[
                                    const SizedBox(height: 16),
                                    const Divider(),
                                    const SizedBox(height: 16),
                                    InkWell(
                                      onTap: _pickLicense,
                                      borderRadius: BorderRadius.circular(8),
                                      child: Container(
                                        height: 200,
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: _licensePhoto == null ? Colors.grey : campusGreen,
                                            width: 2,
                                            style: BorderStyle.solid,
                                          ),
                                          borderRadius: BorderRadius.circular(8),
                                          color: Colors.grey[50],
                                        ),
                                        child: _licensePhoto == null
                                            ? Column(
                                                mainAxisAlignment: MainAxisAlignment.center,
                                                children: const [
                                                  Icon(Icons.add_a_photo, size: 48, color: Colors.grey),
                                                  SizedBox(height: 8),
                                                  Text(
                                                    'Tap to upload driver license',
                                                    style: TextStyle(color: Colors.grey, fontSize: 14),
                                                  ),
                                                ],
                                              )
                                            : ClipRRect(
                                                borderRadius: BorderRadius.circular(8),
                                                child: Image.file(
                                                  _licensePhoto!,
                                                  fit: BoxFit.cover,
                                                ),
                                              ),
                                      ),
                                    ),
                                    if (_licensePhoto != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 12),
                                        child: Row(
                                          children: [
                                            const Icon(Icons.check_circle, color: campusGreen, size: 16),
                                            const SizedBox(width: 6),
                                            const Text(
                                              'License photo selected',
                                              style: TextStyle(color: campusGreen, fontSize: 12),
                                            ),
                                            const Spacer(),
                                            TextButton.icon(
                                              onPressed: () => setState(() => _licensePhoto = null),
                                              icon: const Icon(Icons.close, size: 16),
                                              label: const Text('Remove'),
                                              style: TextButton.styleFrom(foregroundColor: Colors.red),
                                            ),
                                          ],
                                        ),
                                      ),
                                    const SizedBox(height: 16),
                                    SizedBox(
                                      width: double.infinity,
                                      height: 48,
                                      child: ElevatedButton.icon(
                                        onPressed: _uploadLicense,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: campusGreen,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                        ),
                                        icon: const Icon(Icons.cloud_upload),
                                        label: const Text(
                                          'Upload License',
                                          style: TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                    ),
                                  ],

                                  if (completed)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: Row(
                                        children: [
                                          Icon(Icons.check_circle, color: campusGreen, size: 18),
                                          const SizedBox(width: 6),
                                          const Text(
                                            'Completed',
                                            style: TextStyle(
                                              color: campusGreen,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                      );
                    }),

                    // Next Steps Card
                    if (allCompleted)
                      Card(
                        color: Colors.green.shade50,
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: const [
                                  Icon(Icons.check_circle, color: Colors.green, size: 24),
                                  SizedBox(width: 8),
                                  Text(
                                    'All set! 🎉',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Your registration has been approved by admin!\n\nYou can now go online to start receiving ride requests. Good luck out there!',
                                style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (_checklistItems[0]['completed'] as bool)
                      Card(
                        color: Colors.orange.shade50,
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: const [
                                  Icon(Icons.hourglass_empty, color: Colors.orange, size: 24),
                                  SizedBox(width: 8),
                                  Text(
                                    'Waiting for approval...',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.orange,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Your license has been uploaded! Our admin team is reviewing your registration.\n\nYou\'ll receive a notification as soon as you\'re approved.',
                                style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      const SizedBox(height: 16),

                    // Continue Button
                    if (allCompleted)
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: campusGreen,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text(
                            'Go to Dashboard',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}
