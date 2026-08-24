import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../theme/skin_tokens.dart';
import '../../providers/theme_provider.dart';

/// A dependency-free shimmer effect — animates a gradient sweeping across
/// its child. Used to show skeleton loading cards (train list, station
/// board, etc.) instead of a blocking spinner, so the screen's shape is
/// visible immediately while data loads.
class ShimmerBox extends StatefulWidget {
  final double? width;
  final double height;
  final BorderRadius borderRadius;

  const ShimmerBox({
    super.key,
    this.width,
    this.height = 16,
    this.borderRadius = const BorderRadius.all(Radius.circular(6)),
  });

  @override
  State<ShimmerBox> createState() => _ShimmerBoxState();
}

class _ShimmerBoxState extends State<ShimmerBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = SkinTokens.of(context.watch<ThemeProvider>().skin).brightness ==
        Brightness.dark;
    final base = dark ? Colors.white.withValues(alpha: 0.06) : Colors.grey.shade300;
    final highlight =
        dark ? Colors.white.withValues(alpha: 0.16) : Colors.grey.shade100;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: widget.borderRadius,
            gradient: LinearGradient(
              begin: Alignment(-1.0 - _controller.value * 2, 0),
              end: Alignment(1.0 - _controller.value * 2, 0),
              colors: [base, highlight, base],
              stops: const [0.35, 0.5, 0.65],
            ),
          ),
        );
      },
    );
  }
}

/// Skeleton placeholder shaped like a train result card (see
/// `train_list_screen.dart`'s `_trainCard`) — shown while the real search
/// results are loading.
class TrainCardSkeleton extends StatelessWidget {
  const TrainCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final skin = SkinTokens.of(context.watch<ThemeProvider>().skin);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: skin.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: skin.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ShimmerBox(width: 140, height: 16),
                    SizedBox(height: 8),
                    ShimmerBox(width: 80, height: 12),
                  ],
                ),
              ),
              ShimmerBox(width: 50, height: 20, borderRadius: BorderRadius.all(Radius.circular(8))),
            ],
          ),
          SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              ShimmerBox(width: 60, height: 20),
              ShimmerBox(width: 70, height: 12),
              ShimmerBox(width: 60, height: 20),
            ],
          ),
        ],
      ),
    );
  }
}
