import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:app_links/app_links.dart';
import 'splash_screen.dart';
import 'login.dart';
import 'home.dart';
import 'driver_dashboard.dart';
import 'admin_dashboard.dart';
import 'reset_password.dart';
import 'driver_license_resubmit.dart';
import 'driver_onboarding.dart';
import 'driver_notifications.dart';
import 'driver_earnings.dart';

const SUPABASE_URL = "https://muefvrvzobbafgppqdcf.supabase.co";
const SUPABASE_ANON =
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im11ZWZ2cnZ6b2JiYWZncHBxZGNmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM1NDE1OTMsImV4cCI6MjA3OTExNzU5M30.CQHDxPDwBSWA1bUHGk6CcafyHpy6WRGht2uBcO9KI14";

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: SUPABASE_URL, anonKey: SUPABASE_ANON);
  runApp(const CampusRideApp());
}

class CampusRideApp extends StatefulWidget {
  const CampusRideApp({super.key});

  @override
  State<CampusRideApp> createState() => _CampusRideAppState();
}

class _CampusRideAppState extends State<CampusRideApp> {
  late final AppLinks _appLinks;

  @override
  void initState() {
    super.initState();

    // Listen for deep links (password reset email)
    _setupDeepLinkListener();

    // Real-time auth listener
    Supabase.instance.client.auth.onAuthStateChange.listen((event) {
      final session = event.session;

      // User logged out → go to login page
      if (session == null && mounted) {
        navigatorKey.currentState?.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const Login()),
          (_) => false,
        );
      }
    });
  }

  /// Listen for deep links from password reset email
  void _setupDeepLinkListener() {
    // 1) Supabase auth event when token verified via verify endpoint
    Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final event = data.event;
      if (event == AuthChangeEvent.passwordRecovery) {
        debugPrint('🔗 [DeepLink] Password recovery event detected');
        // Only navigate if we're not already on ResetPasswordPage
        final currentRoute = navigatorKey.currentContext;
        if (mounted && currentRoute != null) {
          final isOnResetPage = currentRoute.widget is ResetPasswordPage || 
                               (currentRoute.widget is Scaffold && 
                                currentRoute.findAncestorWidgetOfExactType<ResetPasswordPage>() != null);
          
          if (!isOnResetPage) {
            navigatorKey.currentState?.pushReplacement(
              MaterialPageRoute(builder: (_) => const ResetPasswordPage()),
            );
          } else {
            debugPrint('🔗 [DeepLink] Already on ResetPasswordPage, skipping navigation');
          }
        }
      }
    });

    // 2) Handle direct deep links with token: io.campusride://reset-password?token=...&type=recovery
    _appLinks = AppLinks();

    // Initial link when app is opened from link
    _appLinks.getInitialLink().then((uri) {
      if (uri != null) {
        debugPrint('🔗 [DeepLink] Initial URI: $uri');
        _handlePasswordResetUri(uri);
      }
    }).catchError((e) {
      debugPrint('❌ [DeepLink] getInitialLink error: $e');
    });

    // Stream for links while app is running
    _appLinks.uriLinkStream.listen((uri) {
      if (uri != null) {
        debugPrint('🔗 [DeepLink] Stream URI: $uri');
        _handlePasswordResetUri(uri);
      }
    }, onError: (e) {
      debugPrint('❌ [DeepLink] uriLinkStream error: $e');
    });
  }

  void _handlePasswordResetUri(Uri uri) {
    // Accept either host or path variants
    final isResetPath = uri.host == 'reset-password' || uri.path.contains('reset-password');
    if (!isResetPath) return;

    final token = uri.queryParameters['token'];
    final type = uri.queryParameters['type'];
    if (token == null) {
      debugPrint('⚠️ [DeepLink] No token in URI');
      return;
    }
    if (type != null && type != 'recovery') {
      debugPrint('⚠️ [DeepLink] Unsupported type: $type');
    }

    _verifyRecoveryToken(token);
  }

  Future<void> _verifyRecoveryToken(String token) async {
    try {
      debugPrint('🔐 [DeepLink] Verifying recovery token...');
      final res = await Supabase.instance.client.auth.verifyOTP(
        token: token,
        type: OtpType.recovery,
      );

      if (res.user != null) {
        debugPrint('✅ [DeepLink] Token verified, navigating to ResetPasswordPage');
        if (mounted) {
          navigatorKey.currentState?.pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const ResetPasswordPage()),
            (_) => false,
          );
        }
      } else {
        debugPrint('❌ [DeepLink] Verification returned no user');
      }
    } catch (e) {
      debugPrint('❌ [DeepLink] Token verification failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      home: SplashScreen(onDone: _handleSplashNavigation),
      routes: {
        '/driver_license_resubmit': (context) => const DriverLicenseResubmit(),
        '/driver_onboarding': (context) => const DriverOnboarding(),
        '/driver_notifications': (context) => const DriverNotificationsPage(),
        '/driver_earnings': (context) => const DriverEarningsPage(),
      },
    );
  }

  /// Runs after splash screen finishes
  Future<void> _handleSplashNavigation() async {
    final supabase = Supabase.instance.client;
    final session = supabase.auth.currentSession;

    if (session == null) {
      // No session → show login
      if (!mounted) return;
      navigatorKey.currentState?.pushReplacement(
        MaterialPageRoute(builder: (_) => const Login()),
      );
      return;
    }

    // Session exists → check user role
    final userId = session.user.id;
    String role = 'rider'; // default role

    try {
      // Add timeout to prevent hanging on slow emulators
      final profile = await supabase
          .from('profiles')
          .select('role')
          .eq('id', userId)
          .maybeSingle()
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              debugPrint('⚠️ [Main] Profile fetch timeout - using default role');
              return null;
            },
          );

      if (profile != null) {
        role = profile['role'] ?? 'rider';
      }
    } catch (e) {
      debugPrint('❌ [Main] Error fetching user role: $e');
      // Continue with default role
    }

    if (!mounted) return;

    if (role == 'admin') {
      navigatorKey.currentState?.pushReplacement(
        MaterialPageRoute(builder: (_) => const AdminDashboardPage()),
      );
    } else if (role == 'driver') {
      // Check if driver has completed onboarding (license uploaded)
      try {
        final driver = await supabase
            .from('drivers')
            .select('license_photo_url')
            .eq('id', userId)
            .maybeSingle();

        if (!mounted) return;

        if (driver == null || driver['license_photo_url'] == null) {
          // New driver - show onboarding
          navigatorKey.currentState?.pushReplacement(
            MaterialPageRoute(builder: (_) => const DriverOnboarding()),
          );
        } else {
          // License uploaded - go to dashboard
          navigatorKey.currentState?.pushReplacement(
            MaterialPageRoute(builder: (_) => const DriverDashboard()),
          );
        }
      } catch (e) {
        debugPrint('❌ [Main] Error checking driver onboarding: $e');
        // Fallback to dashboard
        navigatorKey.currentState?.pushReplacement(
          MaterialPageRoute(builder: (_) => const DriverDashboard()),
        );
      }
    } else {
      navigatorKey.currentState?.pushReplacement(
        MaterialPageRoute(builder: (_) => const Home()),
      );
    }
  }
}
