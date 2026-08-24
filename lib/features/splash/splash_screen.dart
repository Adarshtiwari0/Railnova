import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../home/home_screen.dart';
import '../onboarding/onboarding_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // Logo flies in from a tilted 3D angle, "un-rotating" and popping into
  // place with a slight overshoot — like it's landing on the screen.
  late final Animation<double> _scale;
  late final Animation<double> _rotateY;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );

    _scale = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
    );

    _rotateY = Tween<double>(begin: -math.pi / 2.5, end: 0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.7, curve: Curves.easeOutCubic),
      ),
    );

    _fade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.4, curve: Curves.easeIn),
      ),
    );

    _controller.forward();

    Timer(const Duration(milliseconds: 2200), () async {
      if (!mounted) return;

      final prefs = await SharedPreferences.getInstance();
      final seenOnboarding = prefs.getBool("onboarding_seen") ?? false;

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 500),
          pageBuilder: (_, animation, _) => FadeTransition(
            opacity: animation,
            child: seenOnboarding ? const HomeScreen() : const OnboardingScreen(),
          ),
        ),
      );
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 48),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final matrix = Matrix4.identity()
                ..setEntry(3, 2, 0.0015) // perspective depth
                ..rotateY(_rotateY.value)
                ..scaleByDouble(_scale.value, _scale.value, _scale.value, 1.0);

              return Opacity(
                opacity: _fade.value,
                child: Transform(
                  transform: matrix,
                  alignment: Alignment.center,
                  child: child,
                ),
              );
            },
            child: Image.asset(
              "assets/images/railnova_logo.jpeg",
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }
}
