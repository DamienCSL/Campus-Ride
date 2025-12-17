// lib/register.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'login.dart';
import 'driver_register.dart';
import 'error_handler.dart';

class Register extends StatefulWidget {
  const Register({Key? key}) : super(key: key);

  @override
  State<Register> createState() => _RegisterState();
}

class _RegisterState extends State<Register> {
  final _fullNameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _emailError;

  final supabase = Supabase.instance.client;

  // ---------- REGISTER LOGIC ----------
  Future<void> _register() async {
    final fullName = _fullNameCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final password = _passwordCtrl.text;
    final confirmPassword = _confirmPasswordCtrl.text;

    // Validation
    if (fullName.isEmpty ||
        email.isEmpty ||
        password.isEmpty ||
        confirmPassword.isEmpty) {
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
      debugPrint('🔍 [register] Auth user created:');
      debugPrint('   userId: $userId');
      debugPrint('   email: ${res.user!.email}');
      debugPrint('   Attempting to insert profile with id=$userId');

      // Insert profile (only full_name and role)
      try {
        debugPrint('🔄 [register] Inserting into profiles table...');
        await supabase.from('profiles').insert({
          'id': userId,
          'full_name': fullName,
          'role': 'passenger',
        });
        debugPrint('✅ [register] Profile inserted successfully');
      } catch (e) {
        // If insert fails (commonly due to RLS or session not active),
        // save pending profile to SharedPreferences and complete signup.
        ErrorHandler.logError('register - profile insert failed', e);
        try {
          final prefs = await SharedPreferences.getInstance();
          final pending = json.encode({
            'id': userId,
            'full_name': fullName,
            'role': 'passenger',
          });
          await prefs.setString('pending_profile', pending);
        } catch (_) {}
      }

      if (!mounted) return;
      ErrorHandler.showSuccessSnackBar(context, 'Registration successful! Please log in.');

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const Login()),
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      ErrorHandler.logError('register', e);
      ErrorHandler.showErrorSnackBar(context, e);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ErrorHandler.logError('register', e);
      ErrorHandler.showErrorSnackBar(context, AppException(
        message: 'Failed to create profile. Please try again.',
        code: 'profile_creation_failed',
        originalError: e,
      ));
    } catch (e) {
      if (!mounted) return;
      ErrorHandler.logError('register', e);
      ErrorHandler.showErrorSnackBar(context, e);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ---------- UI ----------
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
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Register',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: campusGreen,
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildTextField(
                      _fullNameCtrl,
                      'Full Name',
                      'Enter your full name',
                    ),
                    const SizedBox(height: 16),
                    _buildEmailField(),
                    const SizedBox(height: 16),
                    _buildPasswordField(_passwordCtrl, 'Password'),
                    _passwordStrengthIndicator(_passwordCtrl.text),
                    const SizedBox(height: 16),
                    _buildPasswordField(
                      _confirmPasswordCtrl,
                      'Confirm Password',
                      isConfirm: true,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _register,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: campusGreen,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Register',
                          style: TextStyle(fontSize: 18),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const Login()),
                      ),
                      child: const Text('Already have an account? Log in'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const RegisterDriver(),
                        ),
                      ),
                      child: const Text(
                        "Register as Driver",
                        style: TextStyle(decoration: TextDecoration.underline),
                      ),
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

  // ---------- TEXT FIELDS ----------
  Widget _buildTextField(
    TextEditingController ctrl,
    String label,
    String hint, {
    TextInputType keyboard = TextInputType.text,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: keyboard,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
    );
  }

  Widget _buildEmailField() {
    return TextField(
      controller: _emailCtrl,
      keyboardType: TextInputType.emailAddress,
      decoration: InputDecoration(
        labelText: 'Email',
        hintText: "We'll never share your email",
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
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

  Widget _buildPasswordField(
    TextEditingController ctrl,
    String label, {
    bool isConfirm = false,
  }) {
    return TextField(
      controller: ctrl,
      obscureText: isConfirm ? _obscureConfirm : _obscurePassword,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        suffixIcon: IconButton(
          icon: Icon(
            (isConfirm ? _obscureConfirm : _obscurePassword)
                ? Icons.visibility
                : Icons.visibility_off,
          ),
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
      onChanged: (_) => setState(() {}),
    );
  }

  // ---------- PASSWORD STRENGTH ----------
  Widget _passwordStrengthIndicator(String password) {
    Color color = Colors.red;
    String text = 'Weak';
    if (password.length >= 6 &&
        RegExp(r'[A-Z]').hasMatch(password) &&
        RegExp(r'[0-9]').hasMatch(password)) {
      color = Colors.green;
      text = 'Strong';
    } else if (password.length >= 6) {
      color = Colors.orange;
      text = 'Medium';
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4.0),
      child: Row(
        children: [
          Expanded(child: Container(height: 5, color: color)),
          const SizedBox(width: 8),
          Text(text, style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    super.dispose();
  }
}
