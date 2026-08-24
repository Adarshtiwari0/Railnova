import 'package:flutter/material.dart';

/// Wraps a card with a 3D perspective tilt that follows touch/drag, plus a
/// soft glare sweep. Pure `Matrix4` transforms, no extra package.
class Tilt3D extends StatefulWidget {
  final Widget child;
  final BorderRadius borderRadius;

  /// How strong the tilt is (~0.006 = subtle).
  final double sensitivity;

  const Tilt3D({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.sensitivity = 0.006,
  });

  @override
  State<Tilt3D> createState() => _Tilt3DState();
}

class _Tilt3DState extends State<Tilt3D> {
  Offset _dragPosition = Offset.zero;
  Size _size = Size.zero;
  bool _pressed = false;

  void _onPanUpdate(DragUpdateDetails details, BoxConstraints constraints) {
    setState(() {
      _size = Size(constraints.maxWidth, constraints.maxHeight);
      _dragPosition = details.localPosition;
      _pressed = true;
    });
  }

  void _onPanEnd([_]) {
    setState(() => _pressed = false);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Tilt angle proportional to how far off-center the touch is.
        final centerX = _size.width / 2;
        final centerY = _size.height / 2;
        final dx = _pressed ? (_dragPosition.dx - centerX) : 0.0;
        final dy = _pressed ? (_dragPosition.dy - centerY) : 0.0;

        final rotateY = (dx * widget.sensitivity).clamp(-0.18, 0.18);
        final rotateX = (-dy * widget.sensitivity).clamp(-0.18, 0.18);

        final matrix = Matrix4.identity()
          ..setEntry(3, 2, 0.0012) // perspective depth
          ..rotateX(rotateX)
          ..rotateY(rotateY)
          ..scaleByDouble(_pressed ? 0.98 : 1.0, _pressed ? 0.98 : 1.0, 1.0, 1.0);

        final hasBoundedHeight = constraints.maxHeight.isFinite;

        return GestureDetector(
          onPanDown: (d) => _onPanUpdate(
            DragUpdateDetails(globalPosition: d.globalPosition, localPosition: d.localPosition),
            constraints,
          ),
          onPanUpdate: (d) => _onPanUpdate(d, constraints),
          onPanEnd: _onPanEnd,
          onPanCancel: _onPanEnd,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            width: constraints.maxWidth.isFinite ? constraints.maxWidth : null,
            height: hasBoundedHeight ? constraints.maxHeight : null,
            transform: matrix,
            transformAlignment: Alignment.center,
            child: ClipRRect(
              borderRadius: widget.borderRadius,
              child: Stack(
                fit: hasBoundedHeight ? StackFit.expand : StackFit.loose,
                children: [
                  widget.child,
                  // Soft glare sweep following the touch point — sells the
                  // "glossy 3D surface" illusion.
                  if (_pressed)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: Alignment(
                                (dx / (centerX == 0 ? 1 : centerX)).clamp(-1.0, 1.0),
                                (dy / (centerY == 0 ? 1 : centerY)).clamp(-1.0, 1.0),
                              ),
                              radius: 1.2,
                              colors: [
                                Colors.white.withValues(alpha: 0.16),
                                Colors.white.withValues(alpha: 0.0),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}