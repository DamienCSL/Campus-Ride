// lib/driver_edit_profile.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DriverEditProfilePage extends StatefulWidget {
  final Map<String, dynamic> currentProfile;
  final Map<String, dynamic> currentDriver;

  const DriverEditProfilePage({
    Key? key,
    required this.currentProfile,
    required this.currentDriver,
  }) : super(key: key);

  @override
  State<DriverEditProfilePage> createState() => _DriverEditProfilePageState();
}

class _DriverEditProfilePageState extends State<DriverEditProfilePage> {
  final supabase = Supabase.instance.client;
  late TextEditingController _nameController;
  late TextEditingController _phoneController;
  late TextEditingController _licenseNumberController;
  late TextEditingController _vehicleModelController;
  late TextEditingController _platePlateNumberController;
  late TextEditingController _vehicleColorController;

  File? imageFile;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.currentProfile['full_name'] ?? '',
    );
    _phoneController = TextEditingController(
      text: widget.currentProfile['phone'] ?? '',
    );
    _licenseNumberController = TextEditingController(
      text: widget.currentDriver['license_number'] ?? '',
    );
    _vehicleModelController = TextEditingController(
      text: widget.currentDriver['vehicle_model'] ?? '',
    );
    _platePlateNumberController = TextEditingController(
      text: widget.currentDriver['license_plate'] ?? '',
    );
    _vehicleColorController = TextEditingController(
      text: widget.currentDriver['vehicle_color'] ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _licenseNumberController.dispose();
    _vehicleModelController.dispose();
    _platePlateNumberController.dispose();
    _vehicleColorController.dispose();
    super.dispose();
  }

  Future<void> pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);

    if (picked != null) {
      setState(() {
        imageFile = File(picked.path);
      });
    }
  }

  Future<String?> uploadAvatar(String userId) async {
    if (imageFile == null) return null;

    try {
      // Use user-specific folder: avatars/{userId}/avatar.jpg
      final filePath = "$userId/avatar.jpg";
      final timestamp = DateTime.now().millisecondsSinceEpoch;

      debugPrint('📤 Uploading driver avatar to: $filePath');

      await supabase.storage
          .from("avatars")
          .upload(
            filePath, 
            imageFile!, 
            fileOptions: FileOptions(
              upsert: true,
              contentType: 'image/jpeg',
              cacheControl: '3600',
            )
          );

      // Get public URL without transform, then add cache bust
      final publicUrl = supabase.storage
          .from("avatars")
          .getPublicUrl(filePath);

      // Add timestamp with ? since getPublicUrl returns clean URL without query params
      final finalUrl = '$publicUrl?t=$timestamp';

      debugPrint('✅ Driver avatar uploaded successfully: $finalUrl');
      return finalUrl;
    } catch (e) {
      debugPrint('❌ Driver avatar upload error: $e');
      rethrow;
    }
  }

  Future<void> _saveChanges() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name cannot be empty')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Upload avatar if selected
      String? avatarUrl = await uploadAvatar(user.id);

      // Update profiles table
      await supabase
          .from('profiles')
          .update({
            'full_name': _nameController.text.trim(),
            'phone': _phoneController.text.trim(),
            if (avatarUrl != null) 'avatar_url': avatarUrl,
          })
          .eq('id', user.id);

      // Update drivers table
      await supabase
          .from('drivers')
          .update({
            'license_number': _licenseNumberController.text.trim(),
          })
          .eq('id', user.id);

      // Fetch vehicle_id from drivers table
      final driverRes = await supabase
          .from('drivers')
          .select('vehicle_id')
          .eq('id', user.id)
          .maybeSingle();

      debugPrint('Driver response: $driverRes');
      debugPrint('Vehicle ID: ${driverRes?['vehicle_id']}');

      // Handle vehicle update/creation
      if (driverRes != null && driverRes['vehicle_id'] != null) {
        // Vehicle already linked, update it
        final vehicleId = driverRes['vehicle_id'];
        debugPrint('Updating vehicle with ID: $vehicleId');
        
        try {
          await supabase
              .from('vehicles')
              .update({
                'model': _vehicleModelController.text.trim(),
                'plate_number': _platePlateNumberController.text.trim(),
                'color': _vehicleColorController.text.trim(),
              })
              .eq('id', vehicleId);
          
          debugPrint('Vehicle updated successfully');
        } catch (e) {
          debugPrint('Error updating vehicle: $e');
          // Try upsert instead
          await supabase
              .from('vehicles')
              .upsert({
                'id': vehicleId,
                'driver_id': user.id,
                'model': _vehicleModelController.text.trim(),
                'plate_number': _platePlateNumberController.text.trim(),
                'color': _vehicleColorController.text.trim(),
              });
          debugPrint('Vehicle upserted successfully');
        }
      } else {
        // No vehicle_id, try to find existing vehicle by driver_id
        debugPrint('vehicle_id is null, searching for existing vehicle by driver_id');
        
        final existingVehicle = await supabase
            .from('vehicles')
            .select('id')
            .eq('driver_id', user.id)
            .maybeSingle();
        
        if (existingVehicle != null) {
          // Found existing vehicle, update it and link it
          debugPrint('Found existing vehicle: ${existingVehicle['id']}');
          
          try {
            await supabase
                .from('vehicles')
                .update({
                  'model': _vehicleModelController.text.trim(),
                  'plate_number': _platePlateNumberController.text.trim(),
                  'color': _vehicleColorController.text.trim(),
                })
                .eq('id', existingVehicle['id']);
          } catch (e) {
            debugPrint('Error updating vehicle: $e');
            // Try upsert instead
            await supabase
                .from('vehicles')
                .upsert({
                  'id': existingVehicle['id'],
                  'driver_id': user.id,
                  'model': _vehicleModelController.text.trim(),
                  'plate_number': _platePlateNumberController.text.trim(),
                  'color': _vehicleColorController.text.trim(),
                });
          }
          
          // Update driver with vehicle_id
          await supabase
              .from('drivers')
              .update({'vehicle_id': existingVehicle['id']})
              .eq('id', user.id);
          
          debugPrint('Vehicle updated and linked to driver');
        } else {
          // No vehicle exists, create one using upsert
          debugPrint('No vehicle found, creating new vehicle');
          
          final newVehicle = await supabase
              .from('vehicles')
              .upsert({
                'driver_id': user.id,
                'model': _vehicleModelController.text.trim(),
                'plate_number': _platePlateNumberController.text.trim(),
                'color': _vehicleColorController.text.trim(),
              })
              .select('id');
          
          if (newVehicle.isNotEmpty) {
            final vehicleId = newVehicle[0]['id'];
            debugPrint('Vehicle created with ID: $vehicleId');
            
            // Link vehicle to driver
            await supabase
                .from('drivers')
                .update({'vehicle_id': vehicleId})
                .eq('id', user.id);
            
            debugPrint('Vehicle created and linked to driver');
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Profile updated successfully')),
        );
        Navigator.pop(context, true); // Return true to indicate profile was updated
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const campusGreen = Color(0xFF00BFA6);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: campusGreen,
        elevation: 0,
        title: const Text("Edit Driver Profile"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile Picture Section
            Center(
              child: Column(
                children: [
                  GestureDetector(
                    onTap: pickImage,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 60,
                          backgroundColor: Colors.grey[300],
                          backgroundImage: imageFile != null
                              ? FileImage(imageFile!)
                              : (widget.currentProfile['avatar_url'] != null
                                  ? NetworkImage(widget.currentProfile['avatar_url'])
                                  : null) as ImageProvider?,
                          child: imageFile == null && widget.currentProfile['avatar_url'] == null
                              ? const Icon(Icons.person, size: 60, color: Colors.grey)
                              : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Color(0xFF00BFA6),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.camera_alt,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap to change photo',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Personal Information Section
            const Text(
              'Personal Information',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                  ),
                ],
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildTextField(
                    label: 'Full Name',
                    controller: _nameController,
                    icon: Icons.person,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    label: 'Phone Number',
                    controller: _phoneController,
                    icon: Icons.phone,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Driver & Vehicle Information Section
            const Text(
              'Driver & Vehicle Information',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                  ),
                ],
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _buildTextField(
                    label: 'License Number',
                    controller: _licenseNumberController,
                    icon: Icons.card_membership,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    label: 'Vehicle Model',
                    controller: _vehicleModelController,
                    icon: Icons.directions_car,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    label: 'License Plate',
                    controller: _platePlateNumberController,
                    icon: Icons.confirmation_number,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    label: 'Vehicle Color',
                    controller: _vehicleColorController,
                    icon: Icons.palette,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // Save Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveChanges,
                style: ElevatedButton.styleFrom(
                  backgroundColor: campusGreen,
                  disabledBackgroundColor: Colors.grey[300],
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation(Colors.white),
                        ),
                      )
                    : const Text(
                        'Save Changes',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 16),

            // Cancel Button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _isLoading ? null : () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  side: BorderSide(color: Colors.grey[300]!),
                ),
                child: const Text(
                  'Cancel',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
  }) {
    return TextField(
      controller: controller,
      enabled: !_isLoading,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF00BFA6)),
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
            color: Color(0xFF00BFA6),
            width: 2,
          ),
        ),
        filled: true,
        fillColor: Colors.grey[50],
      ),
    );
  }
}
