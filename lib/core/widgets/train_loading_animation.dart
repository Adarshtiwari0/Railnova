import 'package:flutter/material.dart';

/// A small "train on rails" loading animation with puffs of smoke trailing
/// behind it — used any time the app is waiting on a network call (live
/// status, train search) so the wait feels alive instead of a blank freeze.
/// Renders in white, so give it a colored/dark background behind it.
class TrainLoadingAnimation extends StatefulWidget {
  final String message;

  const TrainLoadingAnimation({super.key, this.message = "Loading..."});

  @override
  State<TrainLoadingAnimation> createState() => _TrainLoadingAnimationState();
}

class _TrainLoadingAnimationState extends State<TrainLoadingAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  static const int _puffCount = 5;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 260,
          height: 70,
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final trainX = _controller.value * 200;

              return Stack(
                alignment: Alignment.centerLeft,
                clipBehavior: Clip.none,
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(height: 3, color: Colors.white70),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: List.generate(
                          18,
                          (i) =>
                              Container(width: 8, height: 3, color: Colors.white38),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(height: 3, color: Colors.white70),
                    ],
                  ),

                  for (int i = 0; i < _puffCount; i++) _smokePuff(i, trainX),

                  Transform.translate(
                    offset: Offset(trainX, 0),
                    child: const Icon(
                      Icons.train_rounded,
                      color: Colors.white,
                      size: 46,
                    ),
                  ),
                ],
              );
            },
          ),
        ),

        const SizedBox(height: 20),

        Text(
          widget.message,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  // Each puff runs on its own phase offset (staggered by index) so they
  // don't all pop into existence at once — fades in behind the train,
  // drifts up-and-back, then fades out as the loop repeats.
  Widget _smokePuff(int index, double trainX) {
    final phase = (_controller.value + (index / _puffCount)) % 1.0;

    final opacity = ((1 - phase) * 0.55).clamp(0.0, 0.55);
    final scale = 0.35 + phase * 1.0;
    final riseY = -phase * 24;
    final driftX = phase * 22;

    return Transform.translate(
      offset: Offset(trainX - 10 - driftX, riseY - 6),
      child: Opacity(
        opacity: opacity,
        child: Transform.scale(
          scale: scale,
          child: Container(
            width: 13,
            height: 13,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
        ),
      ),
    );
  }
}
