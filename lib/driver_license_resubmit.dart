// lib/driver_license_resubmit.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'error_handler.dart';

class DriverLicenseResubmit extends StatefulWidget {
  const DriverLicenseResubmit({Key? key}) : super(key: key);

  @override
  State<DriverLicenseResubmit> createState() => _DriverLicenseResubmitState();
}

class _DriverLicenseResubmitState extends State<DriverLicenseResubmit> {
  final supabase = Supabase.instance.client;
  File? _newLicensePhoto;
  bool _isLoading = false;
  String? _rejectionReason;
  String? _currentLicenseUrl;

  @override
  void initState() {
    super.initState();
    _loadRejectionInfo();
  }

  Future<void> _loadRejectionInfo() async {
    try {
      final user = supabase.auth.currentUser;
      if (user == null) return;

      final driverData = await supabase
          .from('drivers')
          .select('rejection_reason, license_photo_url')
          .eq('id', user.id)
          .maybeSingle();

      if (driverData != null && mounted) {
        setState(() {
          _rejectionReason = driverData['rejection_reason'] as String?;
          _currentLicenseUrl = driverData['license_photo_url'] as String?;
        });
      }
    } catch (e) {
      debugPrint('Error loading rejection info: $e');
    }
  }

  Future<void> _pickNewLicense() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1080,
      imageQuality: 85,
    );

    if (picked != null) {
      setState(() {
        _newLicensePhoto = File(picked.path);
      });
    }
  }

  Future<void> _submitReapplication() async {
    if (_newLicensePhoto == null) {
      ErrorHandler.showErrorSnackBar(context, 'Please upload your new license photo');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final user = supabase.auth.currentUser;
      if (user == null) throw Exception('User not authenticated');

      // Delete old license first if it exists
      if (_currentLicenseUrl != null) {
        try {
          // Extract the path from the public URL
          final urlParts = _currentLicenseUrl!.split('/storage/v1/object/public/driver_licenses/');
          if (urlParts.length == 2) {
            await supabase.storage
                .from('driver_licenses')
                .remove([urlParts[1]]);
          }
        } catch (e) {
          debugPrint('Error deleting old license: $e');
          // Continue anyway - don't fail the upload
        }
      }

      // Upload new license photo
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final licensePhotoPath = '${user.id}/$timestamp.jpg';
      
      await supabase.storage
          .from('driver_licenses')
          .upload(
            licensePhotoPath,
            _newLicensePhoto!,
            fileOptions: const FileOptions(
              contentType: 'image/jpeg',
            ),
          );

      final licensePhotoUrl = supabase.storage
          .from('driver_licenses')
          .getPublicUrl(licensePhotoPath);

      // Reset approval status and update license photo
      await supabase.from('drivers').update({
        'license_photo_url': licensePhotoUrl,
        'is_approved': false,
        'is_rejected': false,
        'rejection_reason': null,
        'rejected_at': null,
      }).eq('id', user.id);

      if (!mounted) return;

      ErrorHandler.showSuccessSnackBar(
        context,
        'License resubmitted successfully! Your application is now pending admin review.',
      );

      // Return to previous screen
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      ErrorHandler.logError('driver_license_resubmit', e);
      ErrorHandler.showErrorSnackBar(context, 'Failed to resubmit license: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const campusGreen = Color(0xFF00BFA6);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Resubmit License'),
        backgroundColor: campusGreen,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Rejection reason card
                  if (_rejectionReason != null)
                    Card(
                      color: Colors.red.shade50,
                      elevation: 2,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.red.shade200, width: 2),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.info_outline, color: Colors.red.shade700),
                                const SizedBox(width: 8),
                                Text(
                                  'Rejection Reason',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: Colors.red.shade700,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _rejectionReason!,
                              style: const TextStyle(fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 24),

                  // Current license (if exists)
                  if (_currentLicenseUrl != null) ...[
                    const Text(
                      'Current License Photo:',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 200,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300, width: 2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          _currentLicenseUrl!,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // New license upload
                  const Text(
                    'Upload New License Photo:',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: _pickNewLicense,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      height: 250,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _newLicensePhoto == null ? Colors.grey : campusGreen,
                          width: 2,
                        ),
                        borderRadius: BorderRadius.circular(12),
                        color: Colors.grey[50],
                      ),
                      child: _newLicensePhoto == null
                          ? Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                Icon(Icons.add_a_photo, size: 64, color: Colors.grey),
                                SizedBox(height: 12),
                                Text(
                                  'Tap to upload new license',
                                  style: TextStyle(
                                    color: Colors.grey,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Make sure the photo is clear and all details are visible',
                                  style: TextStyle(color: Colors.grey, fontSize: 12),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            )
                          : ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.file(
                                _newLicensePhoto!,
                                fit: BoxFit.contain,
                                width: double.infinity,
                              ),
                            ),
                    ),
                  ),

                  if (_newLicensePhoto != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, color: campusGreen, size: 20),
                          const SizedBox(width: 8),
                          const Text(
                            'New license photo selected',
                            style: TextStyle(color: campusGreen, fontSize: 14),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () => setState(() => _newLicensePhoto = null),
                            icon: const Icon(Icons.close, size: 18),
                            label: const Text('Remove'),
                            style: TextButton.styleFrom(foregroundColor: Colors.red),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: 32),

                  // Instructions
                  Card(
                    color: Colors.blue.shade50,
                    elevation: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Row(
                            children: [
                              Icon(Icons.info, color: Colors.blue, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Important Notes:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 8),
                          Text(
                            '• Upload a clear, high-quality photo of your driver\'s license\n'
                            '• Ensure all text and details are readable\n'
                            '• Make sure the license is valid and not expired\n'
                            '• Your application will be reviewed by an admin',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Submit button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _submitReapplication,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: campusGreen,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.upload_file),
                      label: const Text(
                        'Submit for Re-approval',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
