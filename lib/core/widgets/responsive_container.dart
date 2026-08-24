import 'package:flutter/material.dart';

/// Keeps RailNova's screens looking like a real phone app even when opened
/// in a wide browser window (web/desktop) — content is capped at a
/// comfortable app-like width and centered, instead of stretching
/// edge-to-edge across a 1920px laptop screen. On an actual phone-sized
/// viewport this is a no-op (the screen is already narrower than
/// [maxWidth], so nothing visually changes).
///
/// Wrap a screen's Scaffold `body` with this:
/// ```dart
/// Scaffold(
///   body: ResponsiveContainer(child: <existing body>),
/// )
/// ```
class ResponsiveContainer extends StatelessWidget {
  final Widget child;
  final double maxWidth;

  const ResponsiveContainer({
    super.key,
    required this.child,
    this.maxWidth = 520,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;

    // Below maxWidth (any real phone), just pass the child through
    // untouched — zero layout cost, identical to before this widget
    // existed.
    if (screenWidth <= maxWidth) return child;

    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
