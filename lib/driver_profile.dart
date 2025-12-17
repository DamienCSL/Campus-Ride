// lib/driver_profile.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'driver_edit_profile.dart';
import 'login.dart';
import 'change_password.dart';
import 'driver_license_resubmit.dart';
import 'error_handler.dart';

class DriverProfilePage extends StatefulWidget {
  const DriverProfilePage({Key? key}) : super(key: key);

  @override
  State<DriverProfilePage> createState() => _DriverProfilePageState();
}

class _DriverProfilePageState extends State<DriverProfilePage> {
  final supabase = Supabase.instance.client;

  Map<String, dynamic>? profile;
  Map<String, dynamic>? driver;

  @override
  void initState() {
    super.initState();
    loadDriverProfile();
  }

  Future<void> loadDriverProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;

    // Load user profile
    final profileRes = await supabase
        .from('profiles')
        .select()
        .eq('id', user.id)
        .maybeSingle();

    // Load driver details
    final driverRes = await supabase
        .from('drivers')
        .select()
        .eq('id', user.id)
        .maybeSingle();

    // Load vehicle info if driver has a vehicle_id
    if (driverRes != null && driverRes['vehicle_id'] != null) {
      final vehicleRes = await supabase
          .from('vehicles')
          .select()
          .eq('id', driverRes['vehicle_id'])
          .maybeSingle();

      if (vehicleRes != null) {
        // Merge vehicle info into driver object
        driverRes['vehicle_model'] = vehicleRes['model'];
        driverRes['vehicle_color'] = vehicleRes['color'];
        driverRes['license_plate'] = vehicleRes['plate_number'];
      }
    }

    // Get actual trip completion count from rides table
    if (driverRes != null) {
      final completedTripsRes = await supabase
          .from('rides')
          .select('id')
          .eq('driver_id', user.id)
          .eq('status', 'completed');
      
      driverRes['trips_completed'] = (completedTripsRes as List).length;
    }

    setState(() {
      profile = profileRes;
      driver = driverRes;
    });

    debugPrint('📋 Driver profile loaded: ${profileRes?['full_name']}');
    debugPrint('🖼️ Driver avatar URL: ${profileRes?['avatar_url']}');
  }

  Future<void> logout() async {
    await supabase.auth.signOut();
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const Login()),
    );
  }

  @override
  Widget build(BuildContext context) {
    const campusGreen = Color(0xFF00BFA6);

    if (profile == null || driver == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('Loading profile...', style: TextStyle(fontSize: 16)),
              const SizedBox(height: 12),
              TextButton(
                onPressed: loadDriverProfile,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final avatarUrl = profile!['avatar_url'];

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        backgroundColor: campusGreen,
        elevation: 0,
        title: const Text("Driver Profile"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            // Header section with avatar and name
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: campusGreen,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(30),
                  bottomRight: Radius.circular(30),
                ),
              ),
              padding: const EdgeInsets.only(bottom: 30),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Stack(
                    children: [
                      CircleAvatar(
                        radius: 60,
                        backgroundColor: Colors.white,
                        child: CircleAvatar(
                          radius: 56,
                          backgroundColor: Colors.grey[300],
                          backgroundImage: avatarUrl != null && avatarUrl.toString().isNotEmpty
                              ? NetworkImage(avatarUrl)
                              : null,
                          onBackgroundImageError: avatarUrl != null
                              ? (exception, stackTrace) {
                                  debugPrint('❌ Error loading driver avatar: $exception');
                                }
                              : null,
                          child: avatarUrl == null || avatarUrl.toString().isEmpty
                              ? const Icon(Icons.person, size: 60, color: Colors.grey)
                              : null,
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        right: 0,
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.2),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.verified,
                            color: campusGreen,
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    profile!['full_name'] ?? "No name",
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.email, color: Colors.white70, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        supabase.auth.currentUser!.email ?? "",
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Account Settings Card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 8),
                    child: Text(
                      'Account Settings',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        _buildMenuTile(
                          icon: Icons.edit,
                          title: 'Edit Profile',
                          subtitle: 'Update personal and vehicle information',
                          color: campusGreen,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => DriverEditProfilePage(
                                  currentProfile: profile!,
                                  currentDriver: driver!,
                                ),
                              ),
                            ).then((_) => loadDriverProfile());
                          },
                        ),
                        Divider(height: 1, color: Colors.grey[200]),
                        _buildMenuTile(
                          icon: Icons.lock_outline,
                          title: 'Change Password',
                          subtitle: 'Update your password',
                          color: Colors.orange,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const ChangePasswordPage()),
                            );
                          },
                        ),
                        Divider(height: 1, color: Colors.grey[200]),
                        _buildMenuTile(
                          icon: Icons.card_giftcard,
                          title: 'Update License',
                          subtitle: 'Re-upload or update your driver license',
                          color: Colors.blue,
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const DriverLicenseResubmit()),
                            ).then((_) => loadDriverProfile());
                          },
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Driver Details Card
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 8),
                    child: Text(
                      'Driver Information',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildInfoRow(
                          icon: Icons.card_membership,
                          label: 'License Number',
                          value: driver!['license_number'] ?? 'Not set',
                        ),
                        const SizedBox(height: 12),
                        _buildInfoRow(
                          icon: Icons.directions_car,
                          label: 'Vehicle Model',
                          value: driver!['vehicle_model'] ?? 'Not set',
                        ),
                        const SizedBox(height: 12),
                        _buildInfoRow(
                          icon: Icons.confirmation_number,
                          label: 'License Plate',
                          value: driver!['license_plate'] ?? 'Not set',
                        ),
                        const SizedBox(height: 12),
                        _buildInfoRow(
                          icon: Icons.palette,
                          label: 'Vehicle Color',
                          value: driver!['vehicle_color'] ?? 'Not set',
                        ),
                        const SizedBox(height: 12),

                        _buildInfoRow(
                          icon: Icons.star,
                          label: 'Rating',
                          value: (driver!['rating'] ?? 0).toString(),
                        ),
                        const SizedBox(height: 12),
                        _buildInfoRow(
                          icon: Icons.people,
                          label: 'Trips Completed',
                          value: (driver!['trips_completed'] ?? 0).toString(),
                        ),
                        const SizedBox(height: 12),
                        _buildInfoRow(
                          icon: Icons.calendar_today,
                          label: 'Member Since',
                          value: _formatDate(driver!['created_at']),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 30),

                  // Logout Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: logout,
                      icon: const Icon(Icons.logout),
                      label: const Text(
                        "Logout",
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ),

                  const SizedBox(height: 30),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.grey[600]),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDate(dynamic date) {
    if (date == null) return 'Unknown';
    try {
      final DateTime parsedDate = DateTime.parse(date.toString());
      final months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${months[parsedDate.month - 1]} ${parsedDate.year}';
    } catch (e) {
      return 'Unknown';
    }
  }
}
