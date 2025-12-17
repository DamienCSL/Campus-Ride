import 'package:flutter/material.dart';

class SplashScreen extends StatefulWidget {
  final Future<void> Function()? onDone;

  const SplashScreen({Key? key, this.onDone}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    debugPrint('🎬 [Splash] Starting splash screen...');
    _startAnimation();
    _start();
  }

  void _startAnimation() {
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _opacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _controller.forward();
  }

  Future<void> _start() async {
    await Future.delayed(const Duration(seconds: 2)); // animation delay
    debugPrint('🎬 [Splash] Animation complete, calling onDone...');
    if (widget.onDone != null) {
      try {
        await widget.onDone!(); // notify main.dart to navigate
        debugPrint('✅ [Splash] Navigation complete');
      } catch (e) {
        debugPrint('❌ [Splash] Error during navigation: $e');
      }
    } else {
      debugPrint('⚠️ [Splash] onDone is null');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const campusGreen = Color(0xFF00BFA6);

    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: FadeTransition(
          opacity: _opacity,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.location_pin, size: 100, color: campusGreen),
              const SizedBox(height: 20),
              const Text(
                "CampusRide",
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
}
