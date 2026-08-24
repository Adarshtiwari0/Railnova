import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/navigation/smooth_route.dart';
import '../../core/theme/skin_tokens.dart';
import '../../core/widgets/live_station_board_section.dart';
import '../../providers/theme_provider.dart';
import '../live/live_train_screen.dart';

/// A standalone screen for looking up a station's live departure/arrival
/// board directly — without first having to search for a train number.
/// Reuses the same [LiveStationBoardSection] that appears inside
/// [LiveTrainScreen], just without the train-number search box above it.
class StationBoardScreen extends StatelessWidget {
  /// Optional station to open on. Home's LIVE STATION card fills these in so
  /// the board lands on results instead of an empty search field.
  final String? initialStationCode;
  final String? initialStationName;

  const StationBoardScreen({
    super.key,
    this.initialStationCode,
    this.initialStationName,
  });

  @override
  Widget build(BuildContext context) {
    final skin = SkinTokens.of(context.watch<ThemeProvider>().skin);

    return Scaffold(
      backgroundColor: skin.bg,
      appBar: skin.appBar(initialStationName ?? "Station Board"),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: LiveStationBoardSection(
            initialStationCode: initialStationCode,
            initialStationName: initialStationName,
            onTrackTrain: (number) {
              Navigator.push(
                context,
                SmoothRoute(page: LiveTrainScreen(initialTrainNumber: number)),
              );
            },
          ),
        ),
      ),
    );
  }
}
