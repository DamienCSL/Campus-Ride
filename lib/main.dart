import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'splash_screen.dart';
import 'login.dart';
import 'home.dart';
import 'driver_dashboard.dart';

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
  @override
  void initState() {
    super.initState();

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

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      home: SplashScreen(onDone: _handleSplashNavigation),
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
    final profile = await supabase
        .from('profiles')
        .select('role')
        .eq('id', userId)
        .maybeSingle();

    final role = profile?['role'] ?? 'rider';

    if (!mounted) return;

    if (role == 'driver') {
      navigatorKey.currentState?.pushReplacement(
        MaterialPageRoute(builder: (_) => const DriverDashboard()),
      );
    } else {
      navigatorKey.currentState?.pushReplacement(
        MaterialPageRoute(builder: (_) => const Home()),
      );
    }
  }
}
