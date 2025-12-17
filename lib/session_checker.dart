import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'home.dart';
import 'driver_dashboard.dart';
import 'login.dart';

class SessionChecker extends StatefulWidget {
  const SessionChecker({super.key});

  @override
  State<SessionChecker> createState() => _SessionCheckerState();
}

class _SessionCheckerState extends State<SessionChecker> {
  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final supabase = Supabase.instance.client;
    final session = supabase.auth.currentSession;

    // Wait a moment for splash effect
    await Future.delayed(const Duration(milliseconds: 500));

    if (session == null) {
      // No user logged in → go to Login
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const Login()),
      );
      return;
    }

    // User exists → get role
    var profile = await supabase
        .from('profiles')
        .select('role')
        .eq('id', session.user.id)
        .maybeSingle();

    // If profile is missing, attempt to recover from pending_profile saved locally
    if (profile == null) {
      try {
        final prefs = await SharedPreferences.getInstance();
        if (prefs.containsKey('pending_profile')) {
          final pendingRaw = prefs.getString('pending_profile');
          if (pendingRaw != null) {
            final pending = json.decode(pendingRaw);
            if (pending['profile'] != null) {
              try {
                await supabase.from('profiles').insert(pending['profile']);
              } catch (e) {
                // log but continue
                // ignore
              }
            }
            if (pending['driver'] != null) {
              try {
                await supabase.from('drivers').insert(pending['driver']);
              } catch (e) {}
            }
            if (pending['vehicle'] != null) {
              try {
                await supabase.from('vehicles').insert(pending['vehicle']);
              } catch (e) {}
            }
            await prefs.remove('pending_profile');
          }
        } else {
          // No pending data — try to create a minimal profile to avoid stuck state
          final email = session.user.email ?? '';
          final name = email.isNotEmpty ? email.split('@')[0] : 'User';
          try {
            await supabase.from('profiles').insert({
              'id': session.user.id,
              'full_name': name,
              'role': 'passenger',
            });
          } catch (e) {}
        }
      } catch (e) {}

      // Re-query profile after attempted recovery/creation
      profile = await supabase
          .from('profiles')
          .select('role')
          .eq('id', session.user.id)
          .maybeSingle();
    }

    final role = profile?['role'] ?? 'passenger';

    if (!mounted) return;

    if (role == 'driver') {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DriverDashboard()),
      );
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const Home()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
