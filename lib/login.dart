// login.dart
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'home.dart';
import 'register.dart';
import 'driver_dashboard.dart';
import 'driver_onboarding.dart';
import 'admin_dashboard.dart';
import 'error_handler.dart';
import 'forgot_password.dart';

class Login extends StatefulWidget {
  const Login({Key? key}) : super(key: key);

  @override
  State<Login> createState() => _LoginPageState();
}

class _LoginPageState extends State<Login> {
  final TextEditingController emailCtrl = TextEditingController();
  final TextEditingController passwordCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;

  Future<void> _login() async {
    final email = emailCtrl.text.trim();
    final password = passwordCtrl.text.trim();

    // Validation
    if (email.isEmpty || password.isEmpty) {
      ErrorHandler.showErrorSnackBar(context, 'Please fill in all fields');
      return;
    }

    setState(() => _isLoading = true);

    try {
      debugPrint('🔐 [Login] Attempting login for: $email');
      final supabase = Supabase.instance.client;
      
      // Add timeout to sign in
      final res = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw AppException(
            message: 'Login timeout. Check your internet connection and try again.',
            code: 'login_timeout',
          );
        },
      );

      debugPrint('✅ [Login] Sign in successful');
      
      final userId = res.user?.id;
      if (userId == null) {
        throw AppException(
          message: 'Login failed: No user ID returned',
          code: 'no_user_id',
        );
      }

      if (!mounted) return;

      // Fetch user profile with timeout
      debugPrint('📋 [Login] Fetching user profile for: $userId');
      final profile = await supabase
          .from('profiles')
          .select('role')
          .eq('id', userId)
          .maybeSingle()
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              debugPrint('⚠️ [Login] Profile fetch timeout - using default role');
              return null;
            },
          );

      if (!mounted) return;

      final role = profile?['role'] ?? 'rider';
      debugPrint('👤 [Login] User role: $role');

      // Route based on user role
      if (role == 'admin') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const AdminDashboardPage()),
        );
      } else if (role == 'driver') {
        try {
          // Check if license has been uploaded; if not, send to onboarding
          final driver = await supabase
              .from('drivers')
              .select('license_photo_url')
              .eq('id', userId)
              .maybeSingle();

          if (!mounted) return;

          final needsOnboarding = driver == null || driver['license_photo_url'] == null;

          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => needsOnboarding
                  ? const DriverOnboarding()
                  : const DriverDashboard(),
            ),
          );
        } catch (e) {
          debugPrint('❌ [Login] Error checking driver onboarding: $e');
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const DriverDashboard()),
          );
        }
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const Home()),
        );
      }
    } on AuthException catch (e) {
      if (!mounted) return;
      ErrorHandler.logError('login', e);
      ErrorHandler.showErrorSnackBar(context, e);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ErrorHandler.logError('login', e);
      ErrorHandler.showErrorSnackBar(context, AppException(
        message: 'Failed to fetch user profile. Please try again.',
        code: 'fetch_profile_error',
        originalError: e,
      ));
    } catch (e) {
      if (!mounted) return;
      ErrorHandler.logError('login', e);
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

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              const Text(
                "Welcome Back 👋",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              const Text(
                "Login to continue",
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
              const SizedBox(height: 40),

              _buildInputField(
                controller: emailCtrl,
                hint: "Email",
                icon: Icons.email_outlined,
              ),
              const SizedBox(height: 20),

              _buildInputField(
                controller: passwordCtrl,
                hint: "Password",
                icon: Icons.lock_outline,
                isPassword: true,
              ),
              const SizedBox(height: 12),

              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ForgotPasswordPage(),
                      ),
                    );
                  },
                  child: const Text("Forgot Password?"),
                ),
              ),

              const SizedBox(height: 25),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    backgroundColor: campusGreen,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _isLoading ? null : _login,
                  child: _isLoading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text(
                          "Login",
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                ),
              ),

              const Spacer(),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Don't have an account?"),
                  TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const Register()),
                      );
                    },
                    child: const Text("Register"),
                  ),
                ],
              ),
              
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool isPassword = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword ? _obscurePassword : false,
        decoration: InputDecoration(
          icon: Icon(icon, color: Colors.grey),
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility_off : Icons.visibility,
                  ),
                  color: Colors.grey,
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                )
              : null,
          border: InputBorder.none,
          hintText: hint,
        ),
      ),
    );
  }
}
