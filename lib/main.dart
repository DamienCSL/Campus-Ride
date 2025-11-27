import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login.dart';
import 'home.dart';
import 'driver_dashboard.dart';

const SUPABASE_URL = "https://muefvrvzobbafgppqdcf.supabase.co";
const SUPABASE_ANON = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im11ZWZ2cnZ6b2JiYWZncHBxZGNmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM1NDE1OTMsImV4cCI6MjA3OTExNzU5M30.CQHDxPDwBSWA1bUHGk6CcafyHpy6WRGht2uBcO9KI14";

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(url: SUPABASE_URL, anonKey: SUPABASE_ANON);
  runApp(const CampusRideApp());
}

class CampusRideApp extends StatelessWidget {
  const CampusRideApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CampusRide',
      debugShowCheckedModeBanner: false,
      home: const Landing(),
    );
  }
}

class Landing extends StatefulWidget {
  const Landing({Key? key}) : super(key: key);

  @override
  State<Landing> createState() => _LandingState();
}

class _LandingState extends State<Landing> {
  final supabase = Supabase.instance.client;
  bool checking = true;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final session = supabase.auth.currentSession;
    if (session == null) {
      setState(() => checking = false);
      return;
    }

    // load profile to determine role
    final userId = session.user!.id;
    final data = await supabase.from('profiles').select('role').eq('id', userId).maybeSingle();

    final role = data?['role'] ?? 'rider';
    if (role == 'driver') {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const DriverDashboard()));
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const Home()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: checking ? const Center(child: CircularProgressIndicator()) : const Login());
  }
}
