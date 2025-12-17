// lib/register_driver.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'login.dart';
import 'error_handler.dart';

class RegisterDriver extends StatefulWidget {
  const RegisterDriver({Key? key}) : super(key: key);

  @override
  State<RegisterDriver> createState() => _RegisterDriverState();
}

class _RegisterDriverState extends State<RegisterDriver> {
  final _fullNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _licenseCtrl = TextEditingController();
  final _plateCtrl = TextEditingController();
  final _vehicleModelCtrl = TextEditingController();
  final _vehicleColorCtrl = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _emailError;

  final supabase = Supabase.instance.client;

  Future<void> _registerDriver() async {
    final fullName = _fullNameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    final confirmPassword = _confirmPasswordCtrl.text;
    final license = _licenseCtrl.text.trim();
    final plate = _plateCtrl.text.trim();
    final model = _vehicleModelCtrl.text.trim();
    final color = _vehicleColorCtrl.text.trim();

    // Validation
    if ([fullName, email, password, confirmPassword, license, plate, model, color].any((e) => e.isEmpty)) {
      ErrorHandler.showErrorSnackBar(context, 'Please fill in all fields');
      return;
    }

    if (!RegExp(r"^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$").hasMatch(email)) {
      ErrorHandler.showErrorSnackBar(context, 'Invalid email format');
      return;
    }

    if (password.length < 6) {
      ErrorHandler.showErrorSnackBar(context, 'Password must be at least 6 characters');
      return;
    }

    if (password != confirmPassword) {
      ErrorHandler.showErrorSnackBar(context, 'Passwords do not match');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final res = await supabase.auth.signUp(email: email, password: password);

      if (res.user == null) {
        throw AppException(
          message: 'Failed to create account. Please try again.',
          code: 'signup_failed',
        );
      }

      final userId = res.user!.id;
      debugPrint('🔍 [driver_register] Auth user created:');
      debugPrint('   userId: $userId');
      debugPrint('   email: ${res.user!.email}');
      debugPrint('   Attempting to insert profile with id=$userId');

      // create profile + drivers + vehicle inside try; on failure persist pending data
      try {
        debugPrint('🔄 [driver_register] Calling RPC to create profile...');
        final profileRes = await supabase.rpc('create_user_profile', params: {
          'p_id': userId,
          'p_full_name': fullName,
          'p_role': 'driver',
        });
        debugPrint('✅ [driver_register] Profile created via RPC: $profileRes');

        debugPrint('🔄 [driver_register] Inserting into drivers table...');
        // 1) Create driver first (to satisfy vehicles.driver_id FK)
        // Note: license_photo_url is NULL until driver uploads it after login
        final driverInsert = await supabase.from('drivers').insert({
          'id': userId,
          'license_number': license,
          'is_verified': false,
          'is_approved': false,
          'is_rejected': false,
        }).select('id');
        debugPrint('✅ [driver_register] Driver record inserted: $driverInsert');

        debugPrint('🔄 [driver_register] Inserting into vehicles table...');
        // 2) Create vehicle linked to the driver
        final vehicleRes = await supabase.from('vehicles').insert({
          'driver_id': userId,
          'plate_number': plate,
          'model': model,
          'color': color,
        }).select('id');
        debugPrint('✅ [driver_register] Vehicle record inserted: $vehicleRes');

        final vehicleId = vehicleRes[0]['id'];
        debugPrint('   Generated vehicle_id: $vehicleId');

        debugPrint('🔄 [driver_register] Updating driver with vehicle_id...');
        // 3) Update driver with the new vehicle_id
        final driverUpdate = await supabase
            .from('drivers')
            .update({'vehicle_id': vehicleId})
            .eq('id', userId)
            .select('id, vehicle_id, is_approved, is_rejected, is_verified')
            .maybeSingle();
        debugPrint('✅ [driver_register] Driver record updated with vehicle_id: $driverUpdate');

        // Verify the driver exists and is pending approval
        final verifyDriver = await supabase
            .from('drivers')
            .select('id, vehicle_id, is_approved, is_rejected, is_verified')
            .eq('id', userId)
            .maybeSingle();
        debugPrint('🔍 [driver_register] Verification query result: $verifyDriver');

        if (verifyDriver == null) {
          throw Exception('Driver record not found after insert/update!');
        }
      } catch (e) {
        ErrorHandler.logError('driver_register - insert failed', e);
        try {
          final prefs = await SharedPreferences.getInstance();
          final pending = json.encode({
            'profile': {
              'id': userId,
              'full_name': fullName,
              'role': 'driver',
            },
            'driver': {
              'id': userId,
              'license_number': license,
              'verified': false,
            },
            'vehicle': {
              'driver_id': userId,
              'plate_number': plate,
              'model': model,
              'color': color,
            }
          });
          await prefs.setString('pending_profile', pending);
        } catch (_) {}
      }

      if (!mounted) return;
      ErrorHandler.showSuccessSnackBar(context, 'Driver registered successfully! Please log in.');

      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const Login()));
    } on AuthException catch (e) {
      if (!mounted) return;
      ErrorHandler.logError('driver_register', e);
      ErrorHandler.showErrorSnackBar(context, e);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ErrorHandler.logError('driver_register', e);
      
      String errorMsg = 'Failed to complete driver registration';
      if (e.message.contains('duplicate')) {
        errorMsg = 'This information already exists in our system';
      } else if (e.message.contains('permission')) {
        errorMsg = 'You do not have permission to register as a driver';
      }
      
      ErrorHandler.showErrorSnackBar(context, AppException(
        message: errorMsg,
        code: 'driver_registration_failed',
        originalError: e,
      ));
    } catch (e) {
      if (!mounted) return;
      ErrorHandler.logError('driver_register', e);
      ErrorHandler.showErrorSnackBar(context, e);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    const campusGreen = Color(0xFF00BFA6);
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          Center(
            child: SingleChildScrollView(
              child: Container(
                width: size.width * 0.9,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 12, offset: const Offset(0, 6))],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Driver Registration', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: campusGreen)),
                    const SizedBox(height: 24),
                    _buildTextField(_fullNameCtrl, 'Full Name'),
                    const SizedBox(height: 16),
                    _buildEmailField(),
                    const SizedBox(height: 16),
                    _buildPasswordField(_passwordCtrl, 'Password'),
                    const SizedBox(height: 16),
                    _buildPasswordField(_confirmPasswordCtrl, 'Confirm Password', isConfirm: true),
                    const SizedBox(height: 16),
                    _buildTextField(_licenseCtrl, 'License Number'),
                    const SizedBox(height: 16),
                    _buildTextField(_plateCtrl, 'Vehicle Plate Number'),
                    const SizedBox(height: 16),
                    _buildTextField(_vehicleModelCtrl, 'Vehicle Model'),
                    const SizedBox(height: 16),
                    _buildTextField(_vehicleColorCtrl, 'Vehicle Color'),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _registerDriver,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: campusGreen,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('Register', style: TextStyle(fontSize: 18)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const Login())),
                      child: const Text('Already have an account? Log in'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: Colors.black.withOpacity(0.3),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTextField(TextEditingController ctrl, String label) {
    return TextField(
      controller: ctrl,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Widget _buildEmailField() {
    return TextField(
      controller: _emailCtrl,
      keyboardType: TextInputType.emailAddress,
      decoration: InputDecoration(
        labelText: 'Email',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        errorText: _emailError,
      ),
      onChanged: (value) {
        if (!RegExp(r"^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$").hasMatch(value)) {
          setState(() => _emailError = 'Invalid email format');
        } else {
          setState(() => _emailError = null);
        }
      },
    );
  }

  Widget _buildPasswordField(TextEditingController ctrl, String label, {bool isConfirm = false}) {
    return TextField(
      controller: ctrl,
      obscureText: isConfirm ? _obscureConfirm : _obscurePassword,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        suffixIcon: IconButton(
          icon: Icon((isConfirm ? _obscureConfirm : _obscurePassword) ? Icons.visibility : Icons.visibility_off),
          onPressed: () {
            setState(() {
              if (isConfirm) {
                _obscureConfirm = !_obscureConfirm;
              } else {
                _obscurePassword = !_obscurePassword;
              }
            });
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _licenseCtrl.dispose();
    _plateCtrl.dispose();
    _vehicleModelCtrl.dispose();
    _vehicleColorCtrl.dispose();
    super.dispose();
  }
}
