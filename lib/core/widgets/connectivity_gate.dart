import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

/// Wraps the whole app (via `MaterialApp.builder`) and shows a full-screen
/// "Please connect to the internet" message whenever the device has no
/// network — the moment RailNova opens with no connection, and any time it
/// drops mid-use. Disappears automatically the instant connectivity
/// returns; the screen underneath keeps its state the whole time.
class ConnectivityGate extends StatefulWidget {
  final Widget child;

  const ConnectivityGate({super.key, required this.child});

  @override
  State<ConnectivityGate> createState() => _ConnectivityGateState();
}

class _ConnectivityGateState extends State<ConnectivityGate> {
  bool _hasConnection = true;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Timer? _offlineDebounce;

  @override
  void initState() {
    super.initState();
    _checkNow();

    _subscription = Connectivity().onConnectivityChanged.listen(_handleResults);
  }

  Future<void> _checkNow() async {
    final results = await Connectivity().checkConnectivity();
    if (mounted) _handleResults(results);
  }

  /// `connectivity_plus` on web (backed by the browser's `navigator.onLine`)
  /// can report a false "disconnected" for a split second right as the app
  /// loads. Trusting that immediately would flash the full-screen offline
  /// overlay over the splash screen. So: reconnects apply instantly, but a
  /// "disconnected" reading only takes effect if it's still true 2s later —
  /// long enough to ignore the web false-alarm, short enough that a real
  /// dropped connection still shows the overlay quickly.
  void _handleResults(List<ConnectivityResult> results) {
    final connected = results.any((r) => r != ConnectivityResult.none);

    _offlineDebounce?.cancel();

    if (connected) {
      setState(() => _hasConnection = true);
    } else {
      _offlineDebounce = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _hasConnection = false);
      });
    }
  }

  @override
  void dispose() {
    _offlineDebounce?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (!_hasConnection)
          Material(
            color: Colors.black.withValues(alpha: .85),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.wifi_off_rounded,
                        color: Colors.white,
                        size: 48,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      "Please connect to the internet",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "RailNova needs an internet connection to track trains live.",
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .7),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 24),
                    OutlinedButton.icon(
                      onPressed: _checkNow,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                      icon: const Icon(Icons.refresh),
                      label: const Text("Try Again"),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
