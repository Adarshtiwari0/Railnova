import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../pnr/pnr_screen.dart';
import '../live/live_train_screen.dart';
import '../live/favorite_trains_screen.dart';
import '../station_board/station_board_screen.dart';
import '../train_list/train_list_screen.dart';
import '../profile/profile_screen.dart';

import '../../core/theme/skin_tokens.dart';
import '../../core/widgets/theme_picker_sheet.dart';
import '../../core/navigation/smooth_route.dart';
import '../../models/station.dart';
import '../../providers/theme_provider.dart';
import '../../services/station_service.dart';
import '../../services/train_service.dart';
import '../../services/storage/recent_search_service.dart';
import '../showcase/scroll_showcase_screen.dart';

/// Single fixed home layout — route search, live-train tracking and the live
/// station board all happen with inline fields right here (submitting jumps
/// straight to the results screen instead of opening an empty form first).
/// Colors follow the app-wide theme picked in Settings, same as every other
/// screen.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final RecentSearchService _recentService = RecentSearchService();
  final TrainService _trainService = TrainService();

  List<String> recentSearches = [];

  // ---- Route search state ----
  final TextEditingController fromController = TextEditingController();
  final TextEditingController toController = TextEditingController();
  Station? selectedFromStation;
  Station? selectedToStation;
  List<Station> fromSuggestions = [];
  List<Station> toSuggestions = [];
  DateTime selectedDate = DateTime.now();
  Timer? _fromDebounce;
  Timer? _toDebounce;
  bool _findingTrains = false;

  // ---- Live-train-tracking state ----
  final TextEditingController trainController = TextEditingController();
  List<Map<String, dynamic>> trainSuggestions = [];
  Timer? _trainDebounce;

  // ---- Live-station-board state ----
  final TextEditingController stationController = TextEditingController();
  List<Station> stationSuggestions = [];
  Station? selectedBoardStation;
  Timer? _stationDebounce;
  bool _openingBoard = false;

  @override
  void initState() {
    super.initState();
    _loadRecentSearches();
  }

  @override
  void dispose() {
    _fromDebounce?.cancel();
    _toDebounce?.cancel();
    _trainDebounce?.cancel();
    _stationDebounce?.cancel();
    fromController.dispose();
    toController.dispose();
    trainController.dispose();
    stationController.dispose();
    super.dispose();
  }

  Future<void> _loadRecentSearches() async {
    final searches = await _recentService.getRecentSearches();
    if (!mounted) return;
    setState(() => recentSearches = searches);
  }

  // ============================================================
  // Route search — from/to autocomplete + inline "Find Trains"
  // ============================================================

  void _onFromChanged(String value) {
    selectedFromStation = null;
    _fromDebounce?.cancel();

    if (value.trim().isEmpty) {
      setState(() => fromSuggestions = []);
      return;
    }

    _fromDebounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final stations = await StationService.searchStations(value);
        if (!mounted) return;
        setState(() => fromSuggestions = stations);
      } catch (_) {
        if (!mounted) return;
        setState(() => fromSuggestions = []);
      }
    });
  }

  void _onToChanged(String value) {
    selectedToStation = null;
    _toDebounce?.cancel();

    if (value.trim().isEmpty) {
      setState(() => toSuggestions = []);
      return;
    }

    _toDebounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final stations = await StationService.searchStations(value);
        if (!mounted) return;
        setState(() => toSuggestions = stations);
      } catch (_) {
        if (!mounted) return;
        setState(() => toSuggestions = []);
      }
    });
  }

  Future<Station?> _resolveStation(String typed) async {
    try {
      final results = await StationService.searchStations(typed.trim());
      for (final s in results) {
        if (s.name.toLowerCase() == typed.trim().toLowerCase()) return s;
      }
      return results.isNotEmpty ? results.first : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime(2035),
    );
    if (picked != null) setState(() => selectedDate = picked);
  }

  void _swapStations() {
    setState(() {
      final tf = fromController.text;
      fromController.text = toController.text;
      toController.text = tf;
      final ts = selectedFromStation;
      selectedFromStation = selectedToStation;
      selectedToStation = ts;
    });
  }

  Future<void> _findTrains() async {
    if (fromController.text.trim().isEmpty ||
        toController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter both stations")),
      );
      return;
    }

    setState(() => _findingTrains = true);

    Station? fromStation = selectedFromStation;
    Station? toStation = selectedToStation;
    fromStation ??= await _resolveStation(fromController.text);
    toStation ??= await _resolveStation(toController.text);

    if (!mounted) return;
    setState(() => _findingTrains = false);

    if (fromStation == null || toStation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please pick valid stations from the suggestions"),
        ),
      );
      return;
    }

    await _recentService.saveSearch("${fromStation.name} → ${toStation.name}");
    await _loadRecentSearches();
    if (!mounted) return;

    setState(() {
      fromSuggestions = [];
      toSuggestions = [];
    });

    Navigator.push(
      context,
      SmoothRoute(
        page: TrainListScreen(
          fromCode: fromStation.code,
          toCode: toStation.code,
          fromName: fromStation.name,
          toName: toStation.name,
          initialDate: selectedDate,
        ),
      ),
    );
  }

  void _openRecentSearch(String route) async {
    final parts = route.split(" → ");
    if (parts.length != 2) return;

    setState(() => _findingTrains = true);
    final fromStation = await _resolveStation(parts[0]);
    final toStation = await _resolveStation(parts[1]);
    if (!mounted) return;
    setState(() => _findingTrains = false);

    if (fromStation == null || toStation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't reload this route")),
      );
      return;
    }

    Navigator.push(
      context,
      SmoothRoute(
        page: TrainListScreen(
          fromCode: fromStation.code,
          toCode: toStation.code,
          fromName: fromStation.name,
          toName: toStation.name,
        ),
      ),
    );
  }

  // ============================================================
  // Live train tracking — inline train number/name autocomplete
  // ============================================================

  void _onTrainQueryChanged(String query) {
    setState(() {}); // keep suffix icon in sync
    _trainDebounce?.cancel();

    if (query.trim().isEmpty) {
      setState(() => trainSuggestions = []);
      return;
    }

    _trainDebounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final results = await _trainService.lookupTrains(query.trim());
        if (!mounted) return;
        setState(() => trainSuggestions = results);
      } catch (_) {
        // Silent — autocomplete only, "Track Train" button still works.
      }
    });
  }

  void _selectTrainSuggestion(Map<String, dynamic> suggestion) {
    final number = suggestion["number"].toString();
    setState(() {
      trainController.text = number;
      trainSuggestions = [];
    });
    FocusScope.of(context).unfocus();
    _trackLiveTrain();
  }

  void _trackLiveTrain() {
    // Field may hold "12345 · Some Express" from history — pull just the
    // leading number the API expects.
    final raw = trainController.text.trim();
    final number = raw.split(" ").first.replaceAll("·", "").trim();

    if (number.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a train number")),
      );
      return;
    }

    setState(() => trainSuggestions = []);
    FocusScope.of(context).unfocus();

    Navigator.push(
      context,
      SmoothRoute(page: LiveTrainScreen(initialTrainNumber: number)),
    );
  }

  // ============================================================
  // Live station board — inline station autocomplete
  // ============================================================

  void _onStationQueryChanged(String query) {
    selectedBoardStation = null;
    setState(() {}); // keep the clear icon in sync
    _stationDebounce?.cancel();

    if (query.trim().isEmpty) {
      setState(() => stationSuggestions = []);
      return;
    }

    _stationDebounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final results = await StationService.searchStations(query.trim());
        if (!mounted) return;
        setState(() => stationSuggestions = results);
      } catch (_) {
        if (!mounted) return;
        setState(() => stationSuggestions = []);
      }
    });
  }

  void _selectBoardStation(Station station) {
    setState(() {
      stationController.text = station.name;
      selectedBoardStation = station;
      stationSuggestions = [];
    });
    FocusScope.of(context).unfocus();
    _openStationBoard();
  }

  Future<void> _openStationBoard() async {
    if (stationController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Please enter a station")));
      return;
    }

    // Typing a name and hitting the button without touching a suggestion is
    // the common case, so resolve it rather than rejecting it.
    Station? station = selectedBoardStation;
    if (station == null) {
      setState(() => _openingBoard = true);
      station = await _resolveStation(stationController.text);
      if (!mounted) return;
      setState(() => _openingBoard = false);
    }

    if (station == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't find that station")),
      );
      return;
    }

    setState(() => stationSuggestions = []);
    FocusScope.of(context).unfocus();

    Navigator.push(
      context,
      SmoothRoute(
        page: StationBoardScreen(
          initialStationCode: station.code,
          initialStationName: station.name,
        ),
      ),
    );
  }

  // ============================================================
  // UI
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final skin = SkinTokens.of(themeProvider.skin);

    return Scaffold(
      backgroundColor: skin.bg,
      body: SafeArea(
        child: Stack(
          children: [
            // Two offset glows instead of one — the second, cooler one at the
            // bottom keeps the lower half of the screen from reading as a flat
            // dead area once you scroll past the search card.
            _glow(
              top: -90,
              right: -90,
              size: 300,
              color: skin.primary,
              alpha: 0.22,
            ),
            _glow(
              bottom: -120,
              left: -100,
              size: 300,
              color: skin.accent,
              alpha: 0.10,
            ),

            SingleChildScrollView(
              padding: const EdgeInsets.only(bottom: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(skin, themeProvider),
                  _searchCard(skin),
                  const SizedBox(height: 16),
                  _trackCard(skin),
                  const SizedBox(height: 16),
                  _stationCard(skin),
                  const SizedBox(height: 22),
                  _quickActions(skin),
                  if (recentSearches.isNotEmpty) ...[
                    const SizedBox(height: 22),
                    _history(skin),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Header -------------------------------------------------

  /// Brand block and the profile/settings icons live in the same in-flow row.
  /// Previously the icons were a `Positioned` overlay floating above the
  /// scroll view, so they collided with the wordmark and never moved.
  Widget _header(SkinTokens skin, ThemeProvider themeProvider) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 16, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "TRACK · ANYWHERE · ANYTIME",
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 2.6,
                    color: skin.accent,
                    fontWeight: FontWeight.w600,
                    fontFamily: skin.fontFamily,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  "Railnova",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 27,
                    height: 1.05,
                    letterSpacing: -0.4,
                    color: skin.text,
                    fontFamily: skin.fontFamily,
                  ),
                ),
              ],
            ),
          ),
          _circleIcon(
            skin,
            Icons.person_outline,
            () => Navigator.push(
              context,
              SmoothRoute(page: const ProfileScreen()),
            ),
          ),
          const SizedBox(width: 8),
          _circleIcon(
            skin,
            Icons.tune_rounded,
            () => showThemePickerSheet(context, themeProvider),
          ),
        ],
      ),
    );
  }

  // ---- Find trains card ---------------------------------------

  Widget _searchCard(SkinTokens skin) {
    final suggestionsOpen =
        fromSuggestions.isNotEmpty || toSuggestions.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: skin.cardDecoration(radius: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(skin, "FIND TRAINS"),
            const SizedBox(height: 12),

            // From and To share one bordered block split by a hairline, so
            // they read as a single origin→destination pair rather than two
            // unrelated inputs. The swap button sits on that hairline.
            Stack(
              alignment: Alignment.centerRight,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: skin.bg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: skin.border),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Column(
                      children: [
                        _stationField(
                          skin: skin,
                          controller: fromController,
                          hint: "From station",
                          icon: Icons.trip_origin,
                          iconColor: skin.primary,
                          onChanged: _onFromChanged,
                          // Leave room for the swap button so long station
                          // names don't slide underneath it.
                          trailingGap: suggestionsOpen ? 0 : 44,
                        ),
                        if (fromSuggestions.isNotEmpty)
                          _suggestionList(
                            skin: skin,
                            items: fromSuggestions,
                            onPick: (s) => setState(() {
                              fromController.text = s.name;
                              selectedFromStation = s;
                              fromSuggestions = [];
                            }),
                          ),
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: skin.border,
                          indent: 46,
                        ),
                        _stationField(
                          skin: skin,
                          controller: toController,
                          hint: "To station",
                          icon: Icons.place_outlined,
                          iconColor: skin.accent,
                          onChanged: _onToChanged,
                          trailingGap: suggestionsOpen ? 0 : 44,
                        ),
                        if (toSuggestions.isNotEmpty)
                          _suggestionList(
                            skin: skin,
                            items: toSuggestions,
                            onPick: (s) => setState(() {
                              toController.text = s.name;
                              selectedToStation = s;
                              toSuggestions = [];
                            }),
                          ),
                      ],
                    ),
                  ),
                ),
                if (!suggestionsOpen)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _swapButton(skin),
                  ),
              ],
            ),

            const SizedBox(height: 12),
            _dateRow(skin),
            const SizedBox(height: 16),
            _primaryCta(skin),
          ],
        ),
      ),
    );
  }

  /// Circular swap control. Sits on top of the divider between the two
  /// fields (the enclosing Stack centres it vertically), which is where a
  /// swap affordance is expected — it used to hang inside the From field.
  Widget _swapButton(SkinTokens skin) {
    return Material(
      color: skin.card,
      shape: CircleBorder(side: BorderSide(color: skin.border)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _swapStations,
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(Icons.swap_vert_rounded, size: 18, color: skin.primary),
        ),
      ),
    );
  }

  Widget _dateRow(SkinTokens skin) {
    final now = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));

    return Row(
      children: [
        Expanded(
          child: _tappable(
            radius: 14,
            onTap: _pickDate,
            decoration: BoxDecoration(
              color: skin.bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: skin.border),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_month_rounded,
                    color: skin.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      DateFormat('EEE, dd MMM').format(selectedDate),
                      style: TextStyle(
                        color: skin.text,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(Icons.expand_more_rounded, color: skin.dim, size: 18),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _dateChip(skin, "Today", now),
        const SizedBox(width: 6),
        _dateChip(skin, "Tmrw", tomorrow),
      ],
    );
  }

  Widget _dateChip(SkinTokens skin, String label, DateTime date) {
    final active = _isSameDay(selectedDate, date);
    return _tappable(
      radius: 12,
      onTap: () => setState(() => selectedDate = date),
      decoration: BoxDecoration(
        color: active ? skin.primary.withValues(alpha: 0.18) : skin.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: active ? skin.primary : skin.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 13),
        child: Text(
          label,
          style: TextStyle(
            color: active ? skin.primary : skin.dim,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  /// The main call to action. It was an outline-only button, which made it
  /// look weaker than the tinted "Track Train" secondary below it — now it's
  /// the only filled, glowing element on the screen.
  Widget _primaryCta(SkinTokens skin) {
    final fg = _onColor(Color.lerp(skin.primary, skin.primaryDeep, 0.5)!);

    return _tappable(
      radius: 16,
      onTap: _findingTrains ? null : _findTrains,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: [skin.primary, skin.primaryDeep],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: skin.primary.withValues(alpha: 0.38),
            blurRadius: 22,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.center,
        child: _findingTrains
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(color: fg, strokeWidth: 2),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    "FIND TRAINS",
                    style: TextStyle(
                      color: fg,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      fontSize: 14,
                      fontFamily: skin.fontFamily,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded, size: 17, color: fg),
                ],
              ),
      ),
    );
  }

  // ---- Track live train card ----------------------------------

  Widget _trackCard(SkinTokens skin) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: skin.cardDecoration(radius: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(skin, "TRACK LIVE TRAIN"),
            const SizedBox(height: 12),
            _trainField(skin),
          ],
        ),
      ),
    );
  }

  // ---- Live station board card --------------------------------

  /// Mirrors the track card exactly, one tier down in colour. The station
  /// board used to be reachable only as a quick-action tile, which opened an
  /// empty search form — one more screen than the job needs.
  Widget _stationCard(SkinTokens skin) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: skin.cardDecoration(radius: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _label(skin, "LIVE STATION"),
            const SizedBox(height: 12),
            _stationBoardField(skin),
          ],
        ),
      ),
    );
  }

  /// Frosted action pill that lives inside the search field itself, so each
  /// card no longer needs a full-width button under it. It stays translucent
  /// while the field is empty and turns solid the moment there's something to
  /// submit — the field becomes its own affordance.
  Widget _glassAction({
    required SkinTokens skin,
    required Color tint,
    required IconData icon,
    required String tooltip,
    required bool active,
    required VoidCallback? onTap,
    bool busy = false,
  }) {
    final deep = Color.lerp(tint, Colors.black, 0.32)!;
    final fg = active ? _onColor(deep) : tint.withValues(alpha: 0.55);

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 5, 6, 5),
      child: Tooltip(
        message: tooltip,
        child: DecoratedBox(
          // The glow sits outside the clip below, which would otherwise eat it.
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: tint.withValues(alpha: 0.34),
                      blurRadius: 14,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(13),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  color: active ? null : tint.withValues(alpha: 0.10),
                  gradient: active
                      ? LinearGradient(
                          colors: [tint, deep],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : null,
                  border: Border.all(
                    color: active
                        ? Colors.white.withValues(alpha: 0.26)
                        : tint.withValues(alpha: 0.28),
                  ),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: busy ? null : onTap,
                    borderRadius: BorderRadius.circular(13),
                    child: SizedBox(
                      width: 46,
                      height: 38,
                      child: busy
                          ? Center(
                              child: SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: fg,
                                ),
                              ),
                            )
                          : Icon(icon, size: 18, color: fg),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Compact clear cross — a plain [IconButton] enforces a 48px box and would
  /// shove the action pill out of the field.
  Widget _clearButton(SkinTokens skin, VoidCallback onTap) {
    return InkResponse(
      onTap: onTap,
      radius: 18,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(Icons.close_rounded, color: skin.dim, size: 17),
      ),
    );
  }

  // ---- Quick actions ------------------------------------------

  /// Station board used to live here as a third tile; it graduated to its own
  /// inline card above, so only the two shortcuts that genuinely need a full
  /// screen are left.
  Widget _quickActions(SkinTokens skin) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(skin, "QUICK ACTIONS"),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _actionTile(
                  skin: skin,
                  icon: Icons.confirmation_number_outlined,
                  label: "PNR\nStatus",
                  tint: skin.accent,
                  onTap: () => Navigator.push(
                    context,
                    SmoothRoute(page: const PnrScreen()),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _actionTile(
                  skin: skin,
                  icon: Icons.star_rounded,
                  label: "Favorite\nTrains",
                  tint: skin.primary,
                  onTap: () => Navigator.push(
                    context,
                    SmoothRoute(page: const FavoriteTrainsScreen()),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _actionTile(
                  skin: skin,
                  icon: Icons.auto_awesome_rounded,
                  label: "Scroll\nShowcase",
                  tint: skin.accent,
                  onTap: () => Navigator.push(
                    context,
                    SmoothRoute(page: const ScrollShowcaseScreen()),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionTile({
    required SkinTokens skin,
    required IconData icon,
    required String label,
    required Color tint,
    required VoidCallback onTap,
  }) {
    return _tappable(
      radius: 18,
      onTap: onTap,
      decoration: skin.cardDecoration(radius: 18),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: tint.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 19, color: tint),
            ),
            const SizedBox(height: 9),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.25,
                fontWeight: FontWeight.w600,
                color: skin.text,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Search history -----------------------------------------

  Widget _history(SkinTokens skin) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(skin, "SEARCH HISTORY"),
          const SizedBox(height: 6),
          for (final s in recentSearches.take(6)) _historyItem(skin, s),
        ],
      ),
    );
  }

  Widget _historyItem(SkinTokens skin, String route) {
    return _tappable(
      radius: 12,
      onTap: () => _openRecentSearch(route),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: skin.primary.withValues(alpha: 0.08)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 8),
        child: Row(
          children: [
            Icon(Icons.history_rounded, color: skin.primary, size: 15),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                route,
                style: TextStyle(fontSize: 13.5, color: skin.dim),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.north_east_rounded, color: skin.dim, size: 14),
          ],
        ),
      ),
    );
  }

  // ---- Shared pieces ------------------------------------------

  Widget _glow({
    double? top,
    double? bottom,
    double? left,
    double? right,
    required double size,
    required Color color,
    required double alpha,
  }) {
    return Positioned(
      top: top,
      bottom: bottom,
      left: left,
      right: right,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                color.withValues(alpha: alpha),
                color.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Wraps a decorated box in a Material/InkWell pair so taps produce a
  /// ripple clipped to the same radius — the screen was entirely
  /// GestureDetectors before, so nothing gave press feedback.
  Widget _tappable({
    required double radius,
    required VoidCallback? onTap,
    required BoxDecoration decoration,
    required Widget child,
  }) {
    return DecoratedBox(
      decoration: decoration,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          child: child,
        ),
      ),
    );
  }

  Widget _circleIcon(SkinTokens skin, IconData icon, VoidCallback onTap) {
    return Material(
      color: skin.primary.withValues(alpha: 0.15),
      shape: CircleBorder(
        side: BorderSide(color: skin.primary.withValues(alpha: 0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 38,
          height: 38,
          child: Icon(icon, color: skin.primary, size: 18),
        ),
      ),
    );
  }

  Widget _label(SkinTokens skin, String value) {
    return Row(
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
        Text(
          value,
          style: TextStyle(
            fontSize: 10.5,
            letterSpacing: 1.8,
            color: skin.dim,
            fontWeight: FontWeight.w700,
            fontFamily: skin.fontFamily,
          ),
        ),
      ],
    );
  }

  Widget _stationField({
    required SkinTokens skin,
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required Color iconColor,
    required ValueChanged<String> onChanged,
    required double trailingGap,
  }) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: TextStyle(color: skin.text, fontSize: 13.5),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: skin.dim, fontSize: 13.5),
        prefixIcon: Icon(icon, color: iconColor, size: 17),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 46,
          minHeight: 48,
        ),
        suffixIcon: SizedBox(width: trailingGap),
        suffixIconConstraints: BoxConstraints(
          minWidth: trailingGap,
          minHeight: 0,
        ),
        border: InputBorder.none,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 16),
      ),
    );
  }

  Widget _suggestionList({
    required SkinTokens skin,
    required List<Station> items,
    required ValueChanged<Station> onPick,
  }) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: skin.card,
        border: Border(top: BorderSide(color: skin.border)),
      ),
      child: Material(
        color: Colors.transparent,
        child: ListView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: items.length,
          itemBuilder: (context, index) {
            final s = items[index];
            return ListTile(
              dense: true,
              leading: Icon(Icons.train_rounded, color: skin.primary, size: 16),
              title: Text(
                s.name,
                style: TextStyle(color: skin.text, fontSize: 13),
              ),
              subtitle: Text(
                s.code,
                style: TextStyle(color: skin.dim, fontSize: 11),
              ),
              onTap: () => onPick(s),
            );
          },
        ),
      ),
    );
  }

  Widget _trainField(SkinTokens skin) {
    final hasText = trainController.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: skin.bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: skin.border),
          ),
          child: TextField(
            controller: trainController,
            onChanged: _onTrainQueryChanged,
            onSubmitted: (_) => _trackLiveTrain(),
            style: TextStyle(color: skin.text, fontSize: 13.5),
            decoration: InputDecoration(
              hintText: "Train number or name",
              hintStyle: TextStyle(color: skin.dim, fontSize: 13.5),
              prefixIcon: Icon(
                Icons.search_rounded,
                color: skin.accent,
                size: 18,
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 46,
                minHeight: 48,
              ),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasText)
                    _clearButton(skin, () {
                      setState(() {
                        trainController.clear();
                        trainSuggestions = [];
                      });
                    }),
                  _glassAction(
                    skin: skin,
                    tint: skin.accent,
                    icon: Icons.my_location_rounded,
                    tooltip: "Track this train",
                    active: hasText,
                    onTap: _trackLiveTrain,
                  ),
                ],
              ),
              suffixIconConstraints: const BoxConstraints(
                minWidth: 0,
                minHeight: 48,
              ),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        if (trainSuggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: skin.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: skin.border),
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: trainSuggestions.length,
                itemBuilder: (context, index) {
                  final t = trainSuggestions[index];
                  final number = t["number"]?.toString() ?? "";
                  final name = t["name"]?.toString() ?? "";
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      Icons.directions_railway_rounded,
                      color: skin.accent,
                      size: 16,
                    ),
                    title: Text(
                      name.isNotEmpty ? "$number · $name" : number,
                      style: TextStyle(color: skin.text, fontSize: 13),
                    ),
                    onTap: () => _selectTrainSuggestion(t),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  /// Same shape as [_trainField], but the leading glyph is the station code
  /// rather than an icon — codes are what people recognise on a board.
  Widget _stationBoardField(SkinTokens skin) {
    final hasText = stationController.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: skin.bg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: skin.border),
          ),
          child: TextField(
            controller: stationController,
            onChanged: _onStationQueryChanged,
            onSubmitted: (_) => _openStationBoard(),
            style: TextStyle(color: skin.text, fontSize: 13.5),
            decoration: InputDecoration(
              hintText: "Station name or code",
              hintStyle: TextStyle(color: skin.dim, fontSize: 13.5),
              prefixIcon: Icon(
                Icons.location_on_outlined,
                color: skin.primary,
                size: 18,
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 46,
                minHeight: 48,
              ),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasText)
                    _clearButton(skin, () {
                      setState(() {
                        stationController.clear();
                        stationSuggestions = [];
                        selectedBoardStation = null;
                      });
                    }),
                  _glassAction(
                    skin: skin,
                    tint: skin.primary,
                    icon: Icons.podcasts_rounded,
                    tooltip: "View live board",
                    active: hasText,
                    busy: _openingBoard,
                    onTap: _openStationBoard,
                  ),
                ],
              ),
              suffixIconConstraints: const BoxConstraints(
                minWidth: 0,
                minHeight: 48,
              ),
              border: InputBorder.none,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
        ),
        if (stationSuggestions.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 6),
            constraints: const BoxConstraints(maxHeight: 200),
            decoration: BoxDecoration(
              color: skin.card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: skin.border),
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              clipBehavior: Clip.antiAlias,
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: stationSuggestions.length,
                itemBuilder: (context, index) {
                  final s = stationSuggestions[index];
                  return ListTile(
                    dense: true,
                    leading: Text(
                      s.code,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: skin.primary,
                      ),
                    ),
                    title: Text(
                      s.name,
                      style: TextStyle(color: skin.text, fontSize: 13),
                    ),
                    onTap: () => _selectBoardStation(s),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Picks readable text/icon colour for a filled surface, so a filled button
  /// stays legible across all three skins (the accent is a pale mint in one
  /// and a mid green in another).
  Color _onColor(Color background) =>
      ThemeData.estimateBrightnessForColor(background) == Brightness.dark
      ? Colors.white
      : const Color(0xff17102B);
}
