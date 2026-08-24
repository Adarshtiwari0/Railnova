import 'dart:ui';
import 'package:flutter/material.dart';

/// A frosted-glass container: blurs whatever is behind it and overlays a
/// semi-transparent tint + a thin light border, which is what actually sells
/// the "glass" look (blur alone just looks smudgy).
///
/// Pure `dart:ui`/Flutter core — no extra package needed. Works best over a
/// colourful/gradient background; on a flat white background the effect is
/// barely visible, which is expected (there's nothing to blur).
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final double blurSigma;
  final Color tintColor;
  final double tintOpacity;
  final Color borderColor;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 24,
    this.blurSigma = 16,
    this.tintColor = Colors.white,
    this.tintOpacity = 0.14,
    this.borderColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: tintColor.withValues(alpha: tintOpacity),
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: borderColor.withValues(alpha: 0.25), width: 1),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}
