import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/navigation/smooth_route.dart';
import '../../core/theme/skin_tokens.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/train_loading_animation.dart';
import '../../providers/theme_provider.dart';
import '../../services/train_service.dart';
import '../live/live_train_screen.dart';

/// Fetches and displays real train info from RailRadar's
/// `GET /v1/trains/{number}` endpoint (see
/// https://railradar.in/docs/get-train-details) — journey summary, running
/// days, coach position, and the full stop-by-stop route with platforms.
class TrainDetailsScreen extends StatefulWidget {
  final String trainNumber;
  final String trainName;

  const TrainDetailsScreen({
    super.key,
    required this.trainNumber,
    required this.trainName,
  });

  @override
  State<TrainDetailsScreen> createState() => _TrainDetailsScreenState();
}

class _TrainDetailsScreenState extends State<TrainDetailsScreen> {
  final TrainService _trainService = TrainService();

  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = "";

  Map<String, dynamic>? _train;
  List<dynamic> _route = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final data = await _trainService.getTrainDetails(widget.trainNumber);

      if (!mounted) return;

      setState(() {
        _train = data["train"] as Map<String, dynamic>?;
        _route = data["route"] as List? ?? [];
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _hasError = true;
        _errorMessage = e.toString().replaceFirst("Exception: ", "");
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = SkinTokens.of(context.watch<ThemeProvider>().skin);

    return Scaffold(
      backgroundColor: skin.bg,
      appBar: skin.appBar("Train Details"),
      body: _isLoading
          ? Container(
              color: skin.primary,
              width: double.infinity,
              height: double.infinity,
              child: const Center(
                child: TrainLoadingAnimation(message: "Loading train details..."),
              ),
            )
          : _hasError
          ? _buildErrorState()
          : _buildContent(context),
    );
  }

  Widget _buildErrorState() {
    final skin = SkinTokens.of(context.watch<ThemeProvider>().skin);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 70, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(
              "Couldn't load train details",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: skin.text),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: TextStyle(color: skin.dim),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: skin.primaryButtonStyle,
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: const Text("Retry"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final skin = SkinTokens.of(context.watch<ThemeProvider>().skin);
    final train = _train ?? {};
    final source = train["source"] as Map<String, dynamic>?;
    final destination = train["destination"] as Map<String, dynamic>?;
    final runDays = (train["runDays"] as List?)?.map((e) => e.toString()).toList() ?? [];
    final coachPosition = train["coachPosition"]?.toString();
    final coaches = coachPosition?.split("-") ?? [];

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        // Header — gradient + glass, matches the train-list screen's look.
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [skin.primaryDeep, skin.primary],
            ),
          ),
          child: GlassCard(
            borderRadius: 18,
            tintColor: Colors.white,
            tintOpacity: 0.12,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.train, color: Colors.white, size: 30),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.trainName.isNotEmpty
                                ? widget.trainName
                                : (train["name"]?.toString() ?? ""),
                            style: const TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            "${widget.trainNumber}"
                            "${train["type"] != null ? " · ${train["type"]}" : ""}",
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (source != null && destination != null) ...[
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          source["name"]?.toString() ?? "",
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.arrow_forward, color: Colors.white70, size: 18),
                      Expanded(
                        child: Text(
                          destination["name"]?.toString() ?? "",
                          textAlign: TextAlign.right,
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),

        const SizedBox(height: 25),

        if (runDays.isNotEmpty) ...[
          Text(
            "Running Days",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: skin.text),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ["mon", "tue", "wed", "thu", "fri", "sat", "sun"].map((d) {
              final active = runDays.contains(d);
              return Chip(
                label: Text(d.toUpperCase()),
                backgroundColor: active ? skin.primary.withValues(alpha: 0.1) : skin.card,
                labelStyle: TextStyle(
                  color: active ? skin.primaryDeep : skin.dim,
                  fontWeight: active ? FontWeight.bold : FontWeight.normal,
                ),
                side: BorderSide(color: active ? Colors.transparent : skin.border),
              );
            }).toList(),
          ),
        ],

        if (coaches.isNotEmpty) ...[
          const SizedBox(height: 25),
          Text(
            "Coach Position",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: skin.text),
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: coaches
                  .map(
                    (c) => Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: c.toLowerCase().startsWith("engine")
                            ? Colors.grey.shade800
                            : skin.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        c,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: c.toLowerCase().startsWith("engine")
                              ? Colors.white
                              : skin.primaryDeep,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],

        if (_route.isNotEmpty) ...[
          const SizedBox(height: 25),
          Text(
            "Route",
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: skin.text),
          ),
          const SizedBox(height: 12),
          Card(
            color: skin.card,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: List.generate(_route.length, (i) {
                  final stop = _route[i] as Map<String, dynamic>;
                  final station = stop["station"] as Map<String, dynamic>?;
                  final isFirst = i == 0;
                  final isLast = i == _route.length - 1;

                  return _routeStop(
                    stationName: station?["name"]?.toString() ?? "",
                    stationCode: station?["code"]?.toString() ?? "",
                    arrival: stop["arrival"]?.toString(),
                    departure: stop["departure"]?.toString(),
                    platform: stop["platform"]?.toString(),
                    distance: stop["distance"],
                    isFirst: isFirst,
                    isLast: isLast,
                  );
                }),
              ),
            ),
          ),
        ],

        const SizedBox(height: 30),

        SizedBox(
          height: 55,
          width: double.infinity,
          child: ElevatedButton.icon(
            style: skin.primaryButtonStyle,
            icon: const Icon(Icons.my_location),
            label: const Text(
              "Live Status",
              style: TextStyle(fontSize: 18),
            ),
            onPressed: () {
              Navigator.push(
                context,
                SmoothRoute(
                  page: LiveTrainScreen(
                    initialTrainNumber: widget.trainNumber,
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 15),
      ],
    );
  }

  Widget _routeStop({
    required String stationName,
    required String stationCode,
    String? arrival,
    String? departure,
    String? platform,
    dynamic distance,
    required bool isFirst,
    required bool isLast,
  }) {
    final skin = SkinTokens.of(context.watch<ThemeProvider>().skin);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isFirst || isLast ? skin.primary : skin.primary.withValues(alpha: 0.35),
                    border: Border.all(color: skin.primary, width: isFirst || isLast ? 2 : 0),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(width: 2, color: skin.primary.withValues(alpha: 0.18)),
                  ),
              ],
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            stationName.isNotEmpty ? stationName : stationCode,
                            style: TextStyle(fontWeight: FontWeight.w600, color: skin.text),
                          ),
                          if (distance != null)
                            Text(
                              "$distance km",
                              style: TextStyle(fontSize: 12, color: skin.dim),
                            ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (arrival != null || departure != null)
                          Text(
                            [
                              if (arrival != null) "Arr $arrival",
                              if (departure != null) "Dep $departure",
                            ].join(" · "),
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: skin.text),
                          ),
                        if (platform != null)
                          Text(
                            "PF $platform",
                            style: TextStyle(fontSize: 11, color: skin.dim),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
