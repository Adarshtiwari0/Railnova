import 'package:flutter/material.dart';

/// A polished slide+fade page transition, used app-wide instead of the
/// default flat cut from [MaterialPageRoute]. Push with:
/// ```dart
/// Navigator.push(context, SmoothRoute(page: const SearchScreen()));
/// ```
class SmoothRoute<T> extends PageRouteBuilder<T> {
  final Widget page;

  SmoothRoute({required this.page})
    : super(
        transitionDuration: const Duration(milliseconds: 380),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final slide = Tween<Offset>(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic));

          final fade = CurvedAnimation(parent: animation, curve: Curves.easeOut);

          return FadeTransition(
            opacity: fade,
            child: SlideTransition(position: slide, child: child),
          );
        },
      );
}
