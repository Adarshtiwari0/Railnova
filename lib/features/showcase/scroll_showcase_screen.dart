import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../../core/theme/skin_tokens.dart';
import '../../providers/theme_provider.dart';

class ScrollShowcaseScreen extends StatefulWidget {
  const ScrollShowcaseScreen({super.key});

  @override
  State<ScrollShowcaseScreen> createState() => _ScrollShowcaseScreenState();
}

@immutable
class _ScrollState {
  const _ScrollState(this.pixels, this.velocity);
  final double pixels;
  final double velocity;

  @override
  bool operator ==(Object other) =>
      other is _ScrollState &&
      other.pixels == pixels &&
      other.velocity == velocity;

  @override
  int get hashCode => Object.hash(pixels, velocity);
}

class _ScrollShowcaseScreenState extends State<ScrollShowcaseScreen>
    with SingleTickerProviderStateMixin {
  final ScrollController _scroll = ScrollController();
  final ValueNotifier<_ScrollState> _state = ValueNotifier(
    const _ScrollState(0, 0),
  );

  late final Ticker _ticker;
  double _lastPixels = 0;
  double _velocity = 0;
  Duration? _lastFrameTime;
  Duration _idleTime = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onFrame);
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _ticker.dispose();
    _state.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients || !_scroll.position.hasPixels) return;

    final pixels = _scroll.position.pixels;
    if (!_ticker.isActive) {
      _lastPixels = pixels;
      _lastFrameTime = null;
      _idleTime = Duration.zero;
      _ticker.start();
    }

    _publish(pixels);
  }

  void _onFrame(Duration elapsed) {
    final pixels = _scroll.hasClients && _scroll.position.hasPixels
        ? _scroll.position.pixels
        : 0.0;
    final delta = _lastFrameTime == null
        ? const Duration(milliseconds: 16)
        : elapsed - _lastFrameTime!;
    _lastFrameTime = elapsed;

    // Use pixels/second rather than pixels/frame so motion is consistent on
    // 60 Hz and high-refresh-rate devices.
    final seconds = (delta.inMicroseconds / Duration.microsecondsPerSecond)
        .clamp(1 / 240, 0.1)
        .toDouble();
    final raw = (pixels - _lastPixels) / seconds;
    _lastPixels = pixels;

    final smoothing = 1 - math.exp(-12 * seconds);
    _velocity += (raw - _velocity) * smoothing;
    if (_velocity.abs() < 2 && raw.abs() < 0.2) _velocity = 0;

    if (_velocity == 0 && raw.abs() < 0.2) {
      _idleTime += delta;
      if (_idleTime >= const Duration(milliseconds: 160)) {
        _ticker.stop();
        _lastFrameTime = null;
      }
    } else {
      _idleTime = Duration.zero;
    }

    _publish(pixels);
  }

  void _publish(double pixels) {
    final next = _ScrollState(pixels, _velocity);
    if (next != _state.value) _state.value = next;
  }

  @override
  Widget build(BuildContext context) {
    final skin = SkinTokens.of(context.watch<ThemeProvider>().skin);

    return Scaffold(
      backgroundColor: skin.bg,
      body: Stack(
        children: [
          _StarfieldTunnel(state: _state, skin: skin),
          CustomScrollView(
            controller: _scroll,
            slivers: [
              SliverToBoxAdapter(
                child: _HeroSection(state: _state, skin: skin),
              ),
              _RingSection(skin: skin),
              _RouteSection(skin: skin),
              _HorizontalPinSection(skin: skin),
              // ── NEW ──
              _WaveformSection(skin: skin),
              _IndiaMapSection(skin: skin), // ─────────
              SliverToBoxAdapter(
                child: _StatsSection(state: _state, skin: skin),
              ),
              SliverToBoxAdapter(
                child: _OutroSection(state: _state, skin: skin),
              ),
            ],
          ),
          _ScrollProgressBar(controller: _scroll, skin: skin),
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Material(
                  color: skin.card.withValues(alpha: 0.7),
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: IconButton(
                    icon: Icon(Icons.arrow_back_rounded, color: skin.text),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Starfield
// ══════════════════════════════════════════════════════════════

class _StarfieldTunnel extends StatelessWidget {
  const _StarfieldTunnel({required this.state, required this.skin});
  final ValueNotifier<_ScrollState> state;
  final SkinTokens skin;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: ValueListenableBuilder<_ScrollState>(
            valueListenable: state,
            builder: (context, s, _) => CustomPaint(
              painter: _StarfieldPainter(
                offset: s.pixels,
                velocity: s.velocity,
                near: skin.primary,
                far: skin.accent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StarfieldPainter extends CustomPainter {
  _StarfieldPainter({
    required this.offset,
    required this.velocity,
    required this.near,
    required this.far,
  });

  final double offset;
  final double velocity;
  final Color near;
  final Color far;

  static const _depth = 1200.0;
  static const _focal = 620.0;

  static final List<Offset> _seed = () {
    final rng = math.Random(7);
    return List.generate(
      150,
      (_) => Offset(
        (rng.nextDouble() - 0.5) * 1500,
        (rng.nextDouble() - 0.5) * 1500,
      ),
    );
  }();

  static final List<double> _seedZ = () {
    final rng = math.Random(11);
    return List.generate(150, (_) => rng.nextDouble() * _depth);
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final paint = Paint()..strokeCap = StrokeCap.round;
    final streak = (velocity.abs() * 0.1).clamp(0.0, 90.0);

    for (var i = 0; i < _seed.length; i++) {
      final z = (_seedZ[i] - offset * 0.55) % _depth;
      if (z < 1) continue;
      final scale = _focal / z;
      final p = Offset(cx + _seed[i].dx * scale, cy + _seed[i].dy * scale);
      if (p.dx < -120 ||
          p.dx > size.width + 120 ||
          p.dy < -120 ||
          p.dy > size.height + 120) {
        continue;
      }

      final nearness = 1 - z / _depth;
      paint.color = Color.lerp(
        far,
        near,
        nearness,
      )!.withValues(alpha: (nearness * 0.75).clamp(0.0, 1.0));

      if (streak > 2) {
        final dir = p - Offset(cx, cy);
        final len = dir.distance;
        final unit = len < 0.001 ? Offset.zero : dir / len;
        paint.strokeWidth = 0.6 + nearness * 2.0;
        canvas.drawLine(
          p,
          p - unit * streak * nearness * (velocity.isNegative ? -1 : 1),
          paint,
        );
      } else {
        canvas.drawCircle(p, 0.5 + nearness * 1.8, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_StarfieldPainter old) =>
      old.offset != offset ||
      old.velocity != velocity ||
      old.near != near ||
      old.far != far;
}

// ══════════════════════════════════════════════════════════════
// Hero
// ══════════════════════════════════════════════════════════════

class _HeroSection extends StatelessWidget {
  const _HeroSection({required this.state, required this.skin});
  final ValueNotifier<_ScrollState> state;
  final SkinTokens skin;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    return SizedBox(
      height: height,
      child: ValueListenableBuilder<_ScrollState>(
        valueListenable: state,
        builder: (context, s, _) {
          final t = (s.pixels / height).clamp(0.0, 1.0);
          return Center(
            child: Opacity(
              opacity: (1 - t * 1.7).clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, -s.pixels * 0.4),
                child: _VelocitySquish(
                  velocity: s.velocity,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "SCROLL TO EXPLORE",
                          style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 4,
                            fontWeight: FontWeight.w600,
                            color: skin.accent,
                            fontFamily: skin.fontFamily,
                          ),
                        ),
                        const SizedBox(height: 20),
                        _CharReveal(
                          text: "RAILNOVA",
                          skin: skin,
                          progress: (1 - t * 2.2).clamp(0.0, 1.0),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          "Every train. Every platform.\nIn real time.",
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.6,
                            color: skin.dim,
                          ),
                        ),
                        const SizedBox(height: 40),
                        _BobbingChevron(skin: skin),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CharReveal extends StatelessWidget {
  const _CharReveal({
    required this.text,
    required this.skin,
    required this.progress,
  });
  final String text;
  final SkinTokens skin;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final chars = text.split("");
    final slot = 1 / (chars.length + 4);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final (i, ch) in chars.indexed)
          Builder(
            builder: (context) {
              final local = ((progress - slot * i) / (slot * 5)).clamp(
                0.0,
                1.0,
              );
              final eased = Curves.easeOutCubic.transform(local);
              return Opacity(
                opacity: eased,
                child: Transform(
                  alignment: Alignment.bottomCenter,
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.002)
                    ..translateByDouble(0.0, (1 - eased) * 44, 0.0, 1.0)
                    ..rotateX((1 - eased) * 1.2),
                  child: Text(
                    ch,
                    style: TextStyle(
                      fontSize: 52,
                      height: 1.0,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -1,
                      color: skin.text,
                      fontFamily: skin.fontFamily,
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _VelocitySquish extends StatelessWidget {
  const _VelocitySquish({required this.velocity, required this.child});
  final double velocity;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final k = (velocity.abs() / 2700).clamp(0.0, 1.0);
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..scaleByDouble(1 - k * 0.07, 1 + k * 0.13, 1.0, 1.0),
      child: child,
    );
  }
}

class _BobbingChevron extends StatefulWidget {
  const _BobbingChevron({required this.skin});
  final SkinTokens skin;

  @override
  State<_BobbingChevron> createState() => _BobbingChevronState();
}

class _BobbingChevronState extends State<_BobbingChevron>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) => Transform.translate(
        offset: Offset(0, Curves.easeInOut.transform(_c.value) * 10),
        child: child,
      ),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: widget.skin.border),
          color: widget.skin.primary.withValues(alpha: 0.12),
        ),
        child: Icon(
          Icons.keyboard_arrow_down_rounded,
          color: widget.skin.primary,
          size: 22,
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// 3D Ring
// ══════════════════════════════════════════════════════════════

class _RingSection extends StatelessWidget {
  const _RingSection({required this.skin});
  final SkinTokens skin;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    return SliverPersistentHeader(
      delegate: _RingDelegate(
        minExtent: height,
        maxExtent: height * 3.0,
        skin: skin,
      ),
    );
  }
}

class _RingDelegate extends SliverPersistentHeaderDelegate {
  _RingDelegate({
    required this.minExtent,
    required this.maxExtent,
    required this.skin,
  });

  @override
  final double minExtent;
  @override
  final double maxExtent;
  final SkinTokens skin;

  static const _items = [
    ("Live Tracking", Icons.my_location_rounded),
    ("PNR Status", Icons.confirmation_number_outlined),
    ("Station Board", Icons.podcasts_rounded),
    ("Favorites", Icons.star_rounded),
    ("Coach Layout", Icons.view_week_rounded),
    ("Fare Check", Icons.currency_rupee_rounded),
  ];

  static const _radius = 210.0;
  static const _perspective = 0.0011;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final range = maxExtent - minExtent;
    final t = range <= 0 ? 0.0 : (shrinkOffset / range).clamp(0.0, 1.0);
    final base = t * math.pi * 2.4;

    final placed = <({double angle, double x, double z, int index})>[];
    for (var i = 0; i < _items.length; i++) {
      final angle = base + i * 2 * math.pi / _items.length;
      placed.add((
        angle: angle,
        x: math.sin(angle) * _radius,
        z: -math.cos(angle) * _radius,
        index: i,
      ));
    }
    placed.sort((a, b) => b.z.compareTo(a.z));

    return SizedBox(
      height: minExtent,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 30),
            child: _SectionLabel(
              skin: skin,
              text: "PINNED · REAL PERSPECTIVE · DEPTH SORTED",
            ),
          ),
          SizedBox(
            height: 220,
            child: Stack(
              alignment: Alignment.center,
              children: [
                for (final p in placed)
                  Transform(
                    alignment: Alignment.center,
                    transform: Matrix4.identity()
                      ..setEntry(3, 2, _perspective)
                      ..translateByDouble(p.x, 0.0, p.z, 1.0)
                      ..rotateY(-p.angle),
                    child: _RingCard(
                      skin: skin,
                      title: _items[p.index].$1,
                      icon: _items[p.index].$2,
                      nearness: 1 - (p.z + _radius) / (2 * _radius),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 34),
          Text(
            "${(t * 100).round()}% through the pin",
            style: TextStyle(fontSize: 11, letterSpacing: 1.5, color: skin.dim),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_RingDelegate old) =>
      old.minExtent != minExtent ||
      old.maxExtent != maxExtent ||
      old.skin != skin;
}

class _RingCard extends StatelessWidget {
  const _RingCard({
    required this.skin,
    required this.title,
    required this.icon,
    required this.nearness,
  });
  final SkinTokens skin;
  final String title;
  final IconData icon;
  final double nearness;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: (0.12 + nearness * 0.88).clamp(0.0, 1.0),
      child: Container(
        width: 150,
        height: 190,
        padding: const EdgeInsets.all(16),
        decoration: skin
            .cardDecoration(radius: 20)
            .copyWith(
              boxShadow: [
                BoxShadow(
                  color: skin.primary.withValues(alpha: 0.30 * nearness),
                  blurRadius: 34,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                gradient: LinearGradient(
                  colors: [skin.primary, skin.primaryDeep],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Icon(icon, color: Colors.white, size: 19),
            ),
            const Spacer(),
            Text(
              title,
              style: TextStyle(
                fontSize: 15,
                height: 1.2,
                fontWeight: FontWeight.w700,
                color: skin.text,
                fontFamily: skin.fontFamily,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Route line
// ══════════════════════════════════════════════════════════════

class _RouteSection extends StatelessWidget {
  const _RouteSection({required this.skin});
  final SkinTokens skin;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    return SliverPersistentHeader(
      delegate: _RouteDelegate(
        minExtent: height,
        maxExtent: height * 2.4,
        skin: skin,
      ),
    );
  }
}

class _RouteDelegate extends SliverPersistentHeaderDelegate {
  _RouteDelegate({
    required this.minExtent,
    required this.maxExtent,
    required this.skin,
  });

  @override
  final double minExtent;
  @override
  final double maxExtent;
  final SkinTokens skin;

  static const _stops = ["NDLS", "AGC", "BPL", "NGP", "MAS"];

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final range = maxExtent - minExtent;
    final t = range <= 0 ? 0.0 : (shrinkOffset / range).clamp(0.0, 1.0);

    return SizedBox(
      height: minExtent,
      child: Column(
        children: [
          const Spacer(),
          _SectionLabel(skin: skin, text: "PATH DRAWN BY SCROLL POSITION"),
          const SizedBox(height: 8),
          Expanded(
            flex: 6,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _RoutePainter(
                    progress: Curves.easeInOut.transform(t),
                    line: skin.primary,
                    track: skin.border,
                    dotFill: skin.card,
                    glow: skin.accent,
                    label: skin.dim,
                    stops: _stops,
                    fontFamily: skin.fontFamily,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_RouteDelegate old) =>
      old.minExtent != minExtent ||
      old.maxExtent != maxExtent ||
      old.skin != skin;
}

class _RoutePainter extends CustomPainter {
  _RoutePainter({
    required this.progress,
    required this.line,
    required this.track,
    required this.dotFill,
    required this.glow,
    required this.label,
    required this.stops,
    required this.fontFamily,
  });

  final double progress;
  final Color line;
  final Color track;
  final Color dotFill;
  final Color glow;
  final Color label;
  final List<String> stops;
  final String? fontFamily;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final anchors = <Offset>[
      for (final (i, _) in stops.indexed)
        Offset(
          i.isEven ? w * 0.20 : w * 0.78,
          h * (0.08 + 0.84 * (i / (stops.length - 1))),
        ),
    ];

    final path = Path()..moveTo(anchors.first.dx, anchors.first.dy);
    for (var i = 1; i < anchors.length; i++) {
      final prev = anchors[i - 1];
      final cur = anchors[i];
      final midY = (prev.dy + cur.dy) / 2;
      path.cubicTo(prev.dx, midY, cur.dx, midY, cur.dx, cur.dy);
    }

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = track,
    );

    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final metric = metrics.first;
    final travelled = metric.length * progress;

    if (travelled > 0) {
      canvas.drawPath(
        metric.extractPath(0, travelled),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.5
          ..strokeCap = StrokeCap.round
          ..color = line,
      );
    }

    for (final (i, a) in anchors.indexed) {
      final reached = progress >= i / (anchors.length - 1) - 0.02;
      canvas.drawCircle(a, 9, Paint()..color = reached ? line : track);
      canvas.drawCircle(a, 4.5, Paint()..color = dotFill);

      final tp = TextPainter(
        text: TextSpan(
          text: stops[i],
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
            color: reached ? line : label,
            fontFamily: fontFamily,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final dx = i.isEven ? 16.0 : -16.0 - tp.width;
      tp.paint(canvas, a + Offset(dx, -tp.height / 2));
    }

    final tangent = metric.getTangentForOffset(travelled);
    if (tangent != null) {
      _drawTrainMarker(
        canvas,
        position: tangent.position,
        direction: tangent.vector,
        color: glow,
      );
    }
  }

  @override
  bool shouldRepaint(_RoutePainter old) =>
      old.progress != progress ||
      old.line != line ||
      old.track != track ||
      old.dotFill != dotFill ||
      old.glow != glow ||
      old.label != label ||
      old.fontFamily != fontFamily;
}

// ══════════════════════════════════════════════════════════════
// Horizontal pin
// ══════════════════════════════════════════════════════════════

class _HorizontalPinSection extends StatelessWidget {
  const _HorizontalPinSection({required this.skin});
  final SkinTokens skin;

  static const _stations = [
    ("NDLS", "New Delhi"),
    ("BCT", "Mumbai Central"),
    ("HWH", "Howrah"),
    ("MAS", "Chennai Central"),
    ("SBC", "Bengaluru"),
    ("ADI", "Ahmedabad"),
    ("PUNE", "Pune Jn"),
  ];

  static const _cardWidth = 190.0;
  static const _gap = 14.0;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final rowWidth = _stations.length * (_cardWidth + _gap) + 40;
    final travel = math.max(0.0, rowWidth - size.width);

    return SliverPersistentHeader(
      delegate: _HorizontalDelegate(
        minExtent: size.height * 0.72,
        maxExtent: size.height * 0.72 + travel,
        travel: travel,
        skin: skin,
        stations: _stations,
        cardWidth: _cardWidth,
        gap: _gap,
      ),
    );
  }
}

class _HorizontalDelegate extends SliverPersistentHeaderDelegate {
  _HorizontalDelegate({
    required this.minExtent,
    required this.maxExtent,
    required this.travel,
    required this.skin,
    required this.stations,
    required this.cardWidth,
    required this.gap,
  });

  @override
  final double minExtent;
  @override
  final double maxExtent;
  final double travel;
  final SkinTokens skin;
  final List<(String, String)> stations;
  final double cardWidth;
  final double gap;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final range = maxExtent - minExtent;
    final t = range <= 0 ? 0.0 : (shrinkOffset / range).clamp(0.0, 1.0);

    return SizedBox(
      height: minExtent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 34, 20, 20),
            child: _SectionLabel(
              skin: skin,
              text: "VERTICAL SCROLL · HORIZONTAL TRAVEL",
            ),
          ),
          Expanded(
            child: ClipRect(
              child: OverflowBox(
                maxWidth: double.infinity,
                alignment: Alignment.centerLeft,
                child: Transform.translate(
                  offset: Offset(20 - t * travel, 0),
                  child: Row(
                    children: [
                      for (final (i, s) in stations.indexed)
                        Padding(
                          padding: EdgeInsets.only(right: gap),
                          child: _StationCard(
                            skin: skin,
                            code: s.$1,
                            name: s.$2,
                            width: cardWidth,
                            lean: math.sin(
                              (t - i / stations.length) * math.pi * 2,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 26),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_HorizontalDelegate old) =>
      old.minExtent != minExtent ||
      old.maxExtent != maxExtent ||
      old.travel != travel ||
      old.skin != skin;
}

class _StationCard extends StatelessWidget {
  const _StationCard({
    required this.skin,
    required this.code,
    required this.name,
    required this.width,
    required this.lean,
  });
  final SkinTokens skin;
  final String code;
  final String name;
  final double width;
  final double lean;

  @override
  Widget build(BuildContext context) {
    return Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.0012)
        ..rotateY(lean * 0.34),
      child: Container(
        width: width,
        padding: const EdgeInsets.all(18),
        decoration: skin.cardDecoration(radius: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_on_outlined, color: skin.accent, size: 20),
            const SizedBox(height: 30),
            Text(
              code,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: skin.primary,
                fontFamily: skin.fontFamily,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              name,
              style: TextStyle(fontSize: 11.5, color: skin.dim),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// NEW: Waveform — scroll velocity drives wave amplitude
// ══════════════════════════════════════════════════════════════

class _WaveformSection extends StatelessWidget {
  const _WaveformSection({required this.skin});
  final SkinTokens skin;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    return SliverPersistentHeader(
      delegate: _WaveformDelegate(
        minExtent: height * 0.7,
        maxExtent: height * 2.0,
        skin: skin,
      ),
    );
  }
}

class _WaveformDelegate extends SliverPersistentHeaderDelegate {
  _WaveformDelegate({
    required this.minExtent,
    required this.maxExtent,
    required this.skin,
  });

  @override
  final double minExtent;
  @override
  final double maxExtent;
  final SkinTokens skin;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final range = maxExtent - minExtent;
    // t goes 0→1 as the section scrolls through — use it as the "phase"
    // so the wave shifts forward as you scroll.
    final t = range <= 0 ? 0.0 : (shrinkOffset / range).clamp(0.0, 1.0);

    return SizedBox(
      height: minExtent,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _SectionLabel(skin: skin, text: "WAVEFORM · DRIVEN BY SCROLL PHASE"),
          const SizedBox(height: 28),
          RepaintBoundary(
            child: CustomPaint(
              painter: _WaveformPainter(
                phase: t,
                primary: skin.primary,
                accent: skin.accent,
                dim: skin.border,
              ),
              child: const SizedBox(width: double.infinity, height: 180),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            "phase ${(t * 100).round()}%",
            style: TextStyle(fontSize: 11, letterSpacing: 1.5, color: skin.dim),
          ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_WaveformDelegate old) =>
      old.minExtent != minExtent ||
      old.maxExtent != maxExtent ||
      old.skin != skin;
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.phase,
    required this.primary,
    required this.accent,
    required this.dim,
  });

  final double phase;
  final Color primary;
  final Color accent;
  final Color dim;

  @override
  void paint(Canvas canvas, Size size) {
    final cy = size.height / 2;
    final w = size.width;

    // Three layered waves — different freq/amp/speed feel like real audio.
    _drawWave(
      canvas,
      size,
      cy,
      w,
      amp: 55 * phase + 4,
      freq: 1.8,
      phaseShift: phase * math.pi * 4,
      color: primary.withValues(alpha: 0.85),
      strokeWidth: 2.5,
    );

    _drawWave(
      canvas,
      size,
      cy,
      w,
      amp: 32 * phase + 3,
      freq: 3.2,
      phaseShift: phase * math.pi * 6 + 1.0,
      color: accent.withValues(alpha: 0.55),
      strokeWidth: 1.8,
    );

    _drawWave(
      canvas,
      size,
      cy,
      w,
      amp: 18 * phase + 2,
      freq: 5.0,
      phaseShift: phase * math.pi * 8 + 2.1,
      color: dim.withValues(alpha: 0.40),
      strokeWidth: 1.2,
    );
  }

  void _drawWave(
    Canvas canvas,
    Size size,
    double cy,
    double w, {
    required double amp,
    required double freq,
    required double phaseShift,
    required Color color,
    required double strokeWidth,
  }) {
    final path = Path();
    const steps = 200;
    for (var i = 0; i <= steps; i++) {
      final x = w * i / steps;
      final y =
          cy + amp * math.sin(freq * 2 * math.pi * i / steps + phaseShift);
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }

    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_WaveformPainter old) =>
      old.phase != phase ||
      old.primary != primary ||
      old.accent != accent ||
      old.dim != dim;
}

// ══════════════════════════════════════════════════════════════
// NEW: India Map — simplified outline + route draw-on
// ══════════════════════════════════════════════════════════════

class _IndiaMapSection extends StatelessWidget {
  const _IndiaMapSection({required this.skin});
  final SkinTokens skin;

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height;
    return SliverPersistentHeader(
      delegate: _IndiaMapDelegate(
        minExtent: height,
        maxExtent: height * 2.2,
        skin: skin,
      ),
    );
  }
}

class _IndiaMapDelegate extends SliverPersistentHeaderDelegate {
  _IndiaMapDelegate({
    required this.minExtent,
    required this.maxExtent,
    required this.skin,
  });

  @override
  final double minExtent;
  @override
  final double maxExtent;
  final SkinTokens skin;

  // Major city dots: (name, relX 0-1, relY 0-1)
  // Coordinates are approximate relative positions on India's bounding box.
  static const _cities = [
    ("NDLS", "New Delhi", 0.38, 0.18),
    ("BCT", "Mumbai", 0.25, 0.52),
    ("HWH", "Kolkata", 0.72, 0.42),
    ("MAS", "Chennai", 0.52, 0.74),
    ("SBC", "Bengaluru", 0.44, 0.78),
    ("ADI", "Ahmedabad", 0.20, 0.38),
    ("PUNE", "Pune", 0.30, 0.58),
    ("BPL", "Bhopal", 0.40, 0.38),
    ("NGP", "Nagpur", 0.48, 0.46),
  ];

  // Route: NDLS → BPL → NGP → MAS (index into _cities)
  static const _routeIdx = [0, 7, 8, 3];

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final range = maxExtent - minExtent;
    final t = range <= 0 ? 0.0 : (shrinkOffset / range).clamp(0.0, 1.0);

    return SizedBox(
      height: minExtent,
      child: Column(
        children: [
          const SizedBox(height: 32),
          _SectionLabel(
            skin: skin,
            text: "INDIA MAP · ROUTE ANIMATES WITH SCROLL",
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: RepaintBoundary(
                child: CustomPaint(
                  painter: _IndiaMapPainter(
                    progress: Curves.easeInOut.transform(t),
                    cities: _cities,
                    routeIdx: _routeIdx,
                    primary: skin.primary,
                    accent: skin.accent,
                    border: skin.border,
                    text: skin.text,
                    dim: skin.dim,
                    fontFamily: skin.fontFamily,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(_IndiaMapDelegate old) =>
      old.minExtent != minExtent ||
      old.maxExtent != maxExtent ||
      old.skin != skin;
}

class _IndiaMapPainter extends CustomPainter {
  _IndiaMapPainter({
    required this.progress,
    required this.cities,
    required this.routeIdx,
    required this.primary,
    required this.accent,
    required this.border,
    required this.text,
    required this.dim,
    required this.fontFamily,
  });

  final double progress;
  final List<(String, String, double, double)> cities;
  final List<int> routeIdx;
  final Color primary;
  final Color accent;
  final Color border;
  final Color text;
  final Color dim;
  final String? fontFamily;

  // Simplified India outline as relative (x, y) points 0-1
  static const _outline = [
    (0.42, 0.02),
    (0.55, 0.03),
    (0.68, 0.08),
    (0.76, 0.12),
    (0.80, 0.20),
    (0.82, 0.28),
    (0.88, 0.32),
    (0.90, 0.40),
    (0.85, 0.46),
    (0.80, 0.50),
    (0.78, 0.56),
    (0.72, 0.58),
    (0.68, 0.64),
    (0.62, 0.70),
    (0.58, 0.76),
    (0.52, 0.84),
    (0.48, 0.90),
    (0.44, 0.96),
    (0.40, 0.90),
    (0.36, 0.84),
    (0.32, 0.76),
    (0.28, 0.68),
    (0.22, 0.62),
    (0.16, 0.56),
    (0.12, 0.48),
    (0.10, 0.40),
    (0.14, 0.32),
    (0.18, 0.26),
    (0.22, 0.20),
    (0.26, 0.14),
    (0.32, 0.08),
    (0.38, 0.04),
    (0.42, 0.02),
  ];

  Offset _pt(double rx, double ry, Size size) =>
      Offset(rx * size.width, ry * size.height);

  @override
  void paint(Canvas canvas, Size size) {
    // 1. Draw India outline (faint)
    final outlinePath = Path();
    for (final (i, pt) in _outline.indexed) {
      final o = _pt(pt.$1, pt.$2, size);
      i == 0 ? outlinePath.moveTo(o.dx, o.dy) : outlinePath.lineTo(o.dx, o.dy);
    }
    outlinePath.close();

    canvas.drawPath(
      outlinePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = border,
    );
    canvas.drawPath(
      outlinePath,
      Paint()
        ..style = PaintingStyle.fill
        ..color = primary.withValues(alpha: 0.04),
    );

    // 2. Build route path between selected cities
    final routePoints = routeIdx
        .map((i) => _pt(cities[i].$3, cities[i].$4, size))
        .toList();

    final routePath = Path()
      ..moveTo(routePoints.first.dx, routePoints.first.dy);
    for (var i = 1; i < routePoints.length; i++) {
      final prev = routePoints[i - 1];
      final cur = routePoints[i];
      final midY = (prev.dy + cur.dy) / 2;
      routePath.cubicTo(prev.dx, midY, cur.dx, midY, cur.dx, cur.dy);
    }

    // Full faint route track
    canvas.drawPath(
      routePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = accent.withValues(alpha: 0.22),
    );

    // Animated draw-on
    final metrics = routePath.computeMetrics().toList();
    if (metrics.isNotEmpty) {
      final metric = metrics.first;
      final travelled = metric.length * progress;
      if (travelled > 0) {
        canvas.drawPath(
          metric.extractPath(0, travelled),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round
            ..color = accent,
        );
      }

      // Train head on route
      final tangent = metric.getTangentForOffset(travelled);
      if (tangent != null) {
        _drawTrainMarker(
          canvas,
          position: tangent.position,
          direction: tangent.vector,
          color: accent,
        );
      }
    }

    // 3. City dots + labels
    for (final (i, city) in cities.indexed) {
      final pos = _pt(city.$3, city.$4, size);
      final isOnRoute = routeIdx.contains(i);
      final routePos = routeIdx.indexOf(i);
      final reached =
          isOnRoute && progress >= routePos / (routeIdx.length - 1) - 0.03;

      // Outer glow for route cities
      if (isOnRoute) {
        canvas.drawCircle(
          pos,
          10,
          Paint()..color = (reached ? primary : border).withValues(alpha: 0.25),
        );
      }

      canvas.drawCircle(
        pos,
        isOnRoute ? 6.0 : 3.5,
        Paint()..color = reached ? primary : border,
      );

      // Station code label
      final tp = TextPainter(
        text: TextSpan(
          text: city.$1,
          style: TextStyle(
            fontSize: isOnRoute ? 10.0 : 9.0,
            fontWeight: isOnRoute ? FontWeight.w700 : FontWeight.w500,
            color: reached ? primary : dim,
            fontFamily: fontFamily,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      // Place label so it doesn't overlap the dot — nudge by quadrant
      final lx = city.$3 > 0.5 ? pos.dx - tp.width - 10 : pos.dx + 10;
      final ly = pos.dy - tp.height / 2;
      tp.paint(canvas, Offset(lx, ly));
    }
  }

  @override
  bool shouldRepaint(_IndiaMapPainter old) =>
      old.progress != progress ||
      old.primary != primary ||
      old.accent != accent ||
      old.border != border ||
      old.text != text ||
      old.dim != dim ||
      old.fontFamily != fontFamily;
}

// ══════════════════════════════════════════════════════════════
// Stats
// ══════════════════════════════════════════════════════════════

class _StatsSection extends StatelessWidget {
  const _StatsSection({required this.state, required this.skin});
  final ValueNotifier<_ScrollState> state;
  final SkinTokens skin;

  static const _stats = [
    (13000, "+", "trains tracked daily"),
    (7300, "+", "stations covered"),
    (30, "s", "refresh interval"),
  ];

  @override
  Widget build(BuildContext context) {
    return _EnterReveal(
      state: state,
      builder: (context, p) {
        final eased = Curves.easeOutCubic.transform(p);
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 60, 20, 60),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionLabel(skin: skin, text: "COUNTERS DRIVEN BY POSITION"),
              const SizedBox(height: 28),
              for (final (i, s) in _stats.indexed)
                Builder(
                  builder: (context) {
                    final local = ((eased - i * 0.12) / 0.6).clamp(0.0, 1.0);
                    return Opacity(
                      opacity: local,
                      child: Transform.translate(
                        offset: Offset((1 - local) * 36, 0),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 22),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                "${(s.$1 * local).round()}${s.$2}",
                                style: TextStyle(
                                  fontSize: 38,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: -1.2,
                                  color: skin.text,
                                  fontFamily: skin.fontFamily,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                s.$3.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 10,
                                  letterSpacing: 2,
                                  color: skin.dim,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Outro
// ══════════════════════════════════════════════════════════════

class _OutroSection extends StatelessWidget {
  const _OutroSection({required this.state, required this.skin});
  final ValueNotifier<_ScrollState> state;
  final SkinTokens skin;

  @override
  Widget build(BuildContext context) {
    return _EnterReveal(
      state: state,
      builder: (context, p) {
        final eased = Curves.easeOutCubic.transform(p);
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.9,
          child: Center(
            child: Opacity(
              opacity: eased,
              child: Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0015)
                  ..rotateX((1 - eased) * 0.5)
                  ..scaleByDouble(
                    0.8 + eased * 0.2,
                    0.8 + eased * 0.2,
                    1.0,
                    1.0,
                  ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 30),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        "That's the whole trick.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 30,
                          height: 1.2,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.8,
                          color: skin.text,
                          fontFamily: skin.fontFamily,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        "Offset and velocity in.\nTransforms and paths out.\nNo 3D engine, no packages.",
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          height: 1.7,
                          color: skin.dim,
                        ),
                      ),
                      const SizedBox(height: 34),
                      FilledButton.icon(
                        onPressed: () => Navigator.pop(context),
                        style: FilledButton.styleFrom(
                          backgroundColor: skin.primary,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 26,
                            vertical: 16,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        icon: const Icon(Icons.arrow_back_rounded, size: 18),
                        label: const Text("Back to Railnova"),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════
// Shared
// ══════════════════════════════════════════════════════════════

void _drawTrainMarker(
  Canvas canvas, {
  required Offset position,
  required Offset direction,
  required Color color,
}) {
  canvas.drawCircle(
    position,
    16,
    Paint()..color = color.withValues(alpha: 0.25),
  );

  canvas.save();
  canvas.translate(position.dx, position.dy);
  canvas.rotate(math.atan2(direction.dy, direction.dx));

  final body = RRect.fromRectAndRadius(
    Rect.fromCenter(center: Offset.zero, width: 20, height: 12),
    const Radius.circular(4),
  );
  canvas.drawRRect(body, Paint()..color = color);

  final windowPaint = Paint()..color = Colors.white.withValues(alpha: 0.8);
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(1, -3, 5, 6),
      const Radius.circular(1.5),
    ),
    windowPaint,
  );
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(7, -3, 5, 6),
      const Radius.circular(1.5),
    ),
    windowPaint,
  );
  canvas.restore();
}

class _EnterReveal extends StatelessWidget {
  const _EnterReveal({required this.state, required this.builder});
  final ValueNotifier<_ScrollState> state;
  final Widget Function(BuildContext, double) builder;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<_ScrollState>(
      valueListenable: state,
      builder: (context, _, _) {
        final box = context.findRenderObject() as RenderBox?;
        double p = 0;
        if (box != null && box.hasSize) {
          final viewport = MediaQuery.of(context).size.height;
          final topY = box.localToGlobal(Offset.zero).dy;
          const start = 0.90, end = 0.45;
          p = ((viewport * start - topY) / (viewport * (start - end))).clamp(
            0.0,
            1.0,
          );
        }
        return builder(context, p);
      },
    );
  }
}

class _ScrollProgressBar extends StatelessWidget {
  const _ScrollProgressBar({required this.controller, required this.skin});
  final ScrollController controller;
  final SkinTokens skin;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          double fraction = 0;
          if (controller.hasClients &&
              controller.position.hasContentDimensions) {
            final max = controller.position.maxScrollExtent;
            if (max > 0) {
              fraction = (controller.position.pixels / max).clamp(0.0, 1.0);
            }
          }
          return SafeArea(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: fraction,
                child: Container(
                  height: 3,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [skin.primary, skin.accent],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.skin, required this.text});
  final SkinTokens skin;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 3,
          height: 12,
          decoration: BoxDecoration(
            color: skin.accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1.8,
              fontWeight: FontWeight.w700,
              color: skin.dim,
              fontFamily: skin.fontFamily,
            ),
          ),
        ),
      ],
    );
  }
}
