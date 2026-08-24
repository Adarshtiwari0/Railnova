import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/station.dart';
import '../../services/station_service.dart';
import '../../services/storage/recent_search_service.dart';
import '../train_list/train_list_screen.dart';
import '../../core/navigation/smooth_route.dart';
import '../../core/theme/skin_tokens.dart';
import '../../core/widgets/railnova_button.dart';
import '../../core/widgets/railnova_textfield.dart';
import '../../providers/theme_provider.dart';

class SearchScreen extends StatefulWidget {
  /// Prefills the From/To fields (e.g. when opened from a "Recent Search"
  /// tapped on the Home page). Just display text — the user still needs to
  /// pick a suggestion to resolve the actual station code before searching.
  final String? initialFrom;
  final String? initialTo;

  const SearchScreen({super.key, this.initialFrom, this.initialTo});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController fromController = TextEditingController();
  final TextEditingController toController = TextEditingController();
  final RecentSearchService recentService = RecentSearchService();

  // FIX #6 — FocusNodes let us detect when a field loses focus so we can
  // dismiss its suggestion list before the other field's list appears.
  final FocusNode _fromFocus = FocusNode();
  final FocusNode _toFocus = FocusNode();

  List<String> recentSearches = [];
  DateTime selectedDate = DateTime.now();

  List<Station> fromSuggestions = [];
  List<Station> toSuggestions = [];

  Station? selectedFromStation;
  Station? selectedToStation;

  bool isLoadingFrom = false;
  bool isLoadingTo = false;

  Timer? _fromDebounce;
  Timer? _toDebounce;

  late final AnimationController _swapController;

  // FIX #1 — Cache the animation so it is NEVER recreated inside build().
  // Previously a new CurvedAnimation was leaked on every setState() call.
  late final Animation<double> _swapAnimation;

  bool _swapped = false;

  @override
  void initState() {
    super.initState();

    _swapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    // FIX #1 — Built once, reused forever.
    _swapAnimation = Tween<double>(begin: 0, end: 0.5).animate(
      CurvedAnimation(parent: _swapController, curve: Curves.easeInOutBack),
    );

    // FIX #6 — Dismiss each suggestion list when focus leaves that field.
    _fromFocus.addListener(() {
      if (!_fromFocus.hasFocus) setState(() => fromSuggestions = []);
    });
    _toFocus.addListener(() {
      if (!_toFocus.hasFocus) setState(() => toSuggestions = []);
    });

    if (widget.initialFrom != null) fromController.text = widget.initialFrom!;
    if (widget.initialTo != null) toController.text = widget.initialTo!;

    loadRecentSearches();
  }

  Future<void> loadRecentSearches() async {
    final results = await recentService.getRecentSearches();
    if (!mounted) return;
    // FIX #7 — Mutate state inside setState, not before it.
    setState(() => recentSearches = results);
  }

  Future<void> pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime(2035),
    );
    if (picked != null) setState(() => selectedDate = picked);
  }

  // FIX #2 — Changed from Future<void> to void.
  // onChanged expects void Function(String); returning a Future meant any
  // exception thrown after the first await was silently swallowed.
  void searchFromStation(String value) {
    // Any manual edit invalidates a previously selected suggestion.
    selectedFromStation = null;

    if (value.trim().isEmpty) {
      _fromDebounce?.cancel();
      setState(() {
        fromSuggestions = [];
        isLoadingFrom = false;
      });
      return;
    }

    setState(() => isLoadingFrom = true);

    // Debounce: wait for a pause in typing before hitting the API.
    _fromDebounce?.cancel();
    _fromDebounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final stations = await StationService.searchStations(value);
        if (!mounted) return;
        setState(() {
          fromSuggestions = stations;
          isLoadingFrom = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          isLoadingFrom = false;
          fromSuggestions = [];
        });
        debugPrint("From station search error: $e");
      }
    });
  }

  // FIX #2 — Changed from Future<void> to void.
  void searchToStation(String value) {
    selectedToStation = null;

    if (value.trim().isEmpty) {
      _toDebounce?.cancel();
      setState(() {
        toSuggestions = [];
        isLoadingTo = false;
      });
      return;
    }

    setState(() => isLoadingTo = true);

    _toDebounce?.cancel();
    _toDebounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final stations = await StationService.searchStations(value);
        if (!mounted) return;
        setState(() {
          toSuggestions = stations;
          isLoadingTo = false;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          isLoadingTo = false;
          toSuggestions = [];
        });
        debugPrint("To station search error: $e");
      }
    });
  }

  void swapStations() {
    _swapped = !_swapped;
    _swapped ? _swapController.forward() : _swapController.reverse();

    final temp = fromController.text;
    fromController.text = toController.text;
    toController.text = temp;

    final tempStation = selectedFromStation;
    selectedFromStation = selectedToStation;
    selectedToStation = tempStation;

    setState(() {
      fromSuggestions = [];
      toSuggestions = [];
    });
  }

  // FIX #10 — Only return a station if the name matches EXACTLY.
  // Previously, any first API result was returned as a fallback, which
  // could silently book a completely wrong station.
  Future<Station?> _resolveStation(String typed) async {
    try {
      final results = await StationService.searchStations(typed.trim());
      final exact = results.where(
        (s) => s.name.toLowerCase() == typed.trim().toLowerCase(),
      );
      return exact.isEmpty ? null : exact.first;
    } catch (_) {
      return null;
    }
  }

  Future<void> searchTrain() async {
    if (fromController.text.trim().isEmpty ||
        toController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter both stations")),
      );
      return;
    }

    Station? fromStation = selectedFromStation;
    Station? toStation = selectedToStation;

    // User typed a name but never tapped a suggestion — try to resolve it.
    fromStation ??= await _resolveStation(fromController.text);
    toStation ??= await _resolveStation(toController.text);

    if (!mounted) return;

    if (fromStation == null || toStation == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Please pick valid stations from the suggestions list"),
        ),
      );
      return;
    }

    // FIX #8 — saveSearch wrapped in try-catch so a storage error
    // doesn't crash the app and block the user from navigating.
    try {
      await recentService.saveSearch("${fromStation.name} → ${toStation.name}");
    } catch (e) {
      debugPrint("Could not save recent search: $e");
    }

    // FIX #9 — Refresh the list in the background; do NOT await it.
    // Previously this added a full storage round-trip to navigation latency.
    loadRecentSearches();

    if (!mounted) return;

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

  @override
  Widget build(BuildContext context) {
    final skin = SkinTokens.of(context.watch<ThemeProvider>().skin);

    return Scaffold(
      backgroundColor: skin.bg,
      appBar: skin.appBar("Search Train"),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // FIX #3 — Removed the stray SizedBox(height: 10) that had
            // nothing between it and this SizedBox(height: 8).
            const SizedBox(height: 8),

            // ── From field ──────────────────────────────────────────────
            Column(
              children: [
                // FIX #6 — Focus widget reports focus changes without
                // requiring RailNovaTextField to accept a FocusNode param.
                Focus(
                  focusNode: _fromFocus,
                  child: RailNovaTextField(
                    controller: fromController,
                    hintText: "From Station",
                    prefixIcon: Icons.location_on,
                    onChanged: searchFromStation,
                  ),
                ),

                // FIX #5 — Loading indicator (was tracked but never shown).
                if (isLoadingFrom)
                  LinearProgressIndicator(
                    minHeight: 2,
                    color: skin.primary,
                    backgroundColor: skin.border,
                  ),

                if (fromSuggestions.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 5),
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: Material(
                      color: skin.card,
                      borderRadius: BorderRadius.circular(10),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: fromSuggestions.length,
                        itemBuilder: (context, index) {
                          final station = fromSuggestions[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: skin.primary.withValues(
                                alpha: 0.12,
                              ),
                              child: Icon(
                                Icons.train,
                                size: 18,
                                color: skin.primaryDeep,
                              ),
                            ),
                            title: Text(
                              station.name,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: skin.text,
                              ),
                            ),
                            subtitle: Text(
                              station.code,
                              style: TextStyle(color: skin.dim),
                            ),
                            onTap: () {
                              fromController.text = station.name;
                              selectedFromStation = station;
                              setState(() => fromSuggestions = []);
                            },
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 18),

            // ── Swap button ─────────────────────────────────────────────
            Center(
              child: CircleAvatar(
                radius: 22,
                backgroundColor: skin.primary,
                child: IconButton(
                  onPressed: swapStations,
                  // FIX #1 — Use the cached animation, not a new one.
                  icon: RotationTransition(
                    turns: _swapAnimation,
                    child: const Icon(Icons.swap_vert, color: Colors.white),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 18),

            // ── To field ────────────────────────────────────────────────
            Column(
              children: [
                Focus(
                  focusNode: _toFocus,
                  child: RailNovaTextField(
                    controller: toController,
                    hintText: "To Station",
                    prefixIcon: Icons.flag,
                    onChanged: searchToStation,
                  ),
                ),

                // FIX #5 — Loading indicator.
                if (isLoadingTo)
                  LinearProgressIndicator(
                    minHeight: 2,
                    color: skin.primary,
                    backgroundColor: skin.border,
                  ),

                if (toSuggestions.isNotEmpty)
                  Container(
                    margin: const EdgeInsets.only(top: 5),
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: Material(
                      color: skin.card,
                      borderRadius: BorderRadius.circular(10),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: toSuggestions.length,
                        itemBuilder: (context, index) {
                          final station = toSuggestions[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: skin.primary.withValues(
                                alpha: 0.12,
                              ),
                              child: Icon(
                                Icons.train,
                                size: 18,
                                color: skin.primaryDeep,
                              ),
                            ),
                            title: Text(
                              station.name,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: skin.text,
                              ),
                            ),
                            subtitle: Text(
                              station.code,
                              style: TextStyle(color: skin.dim),
                            ),
                            onTap: () {
                              toController.text = station.name;
                              selectedToStation = station;
                              setState(() => toSuggestions = []);
                            },
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 18),

            // ── Date picker ─────────────────────────────────────────────
            InkWell(
              onTap: pickDate,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 15,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  color: skin.card,
                  border: Border.all(color: skin.border),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_month, color: skin.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        DateFormat('dd MMM yyyy').format(selectedDate),
                        style: TextStyle(fontSize: 16, color: skin.text),
                      ),
                    ),
                    Icon(Icons.arrow_drop_down, color: skin.dim),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 30),

            RailNovaButton(
              text: "Search Train",
              icon: Icons.search,
              onPressed: searchTrain,
            ),

            // FIX #4 — Removed the extra SizedBox(height: 30) that was
            // here, giving 60 px of dead space before the section.
            // The SizedBox inside the conditional below is enough.
            if (recentSearches.isNotEmpty) ...[
              const SizedBox(height: 30),

              Row(
                children: [
                  Icon(Icons.history, color: skin.primary),
                  const SizedBox(width: 8),
                  Text(
                    "Recent Searches",
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: skin.text,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              ...recentSearches.map((route) {
                return Card(
                  color: skin.card,
                  elevation: 2,
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: skin.primary.withValues(alpha: 0.12),
                      child: Icon(Icons.train, color: skin.primaryDeep),
                    ),
                    title: Text(route, style: TextStyle(color: skin.text)),
                    trailing: Icon(
                      Icons.arrow_forward_ios,
                      size: 18,
                      color: skin.dim,
                    ),
                    onTap: () {
                      final parts = route.split(" → ");
                      if (parts.length == 2) {
                        setState(() {
                          fromController.text = parts[0];
                          toController.text = parts[1];
                          // Clear stale selections — user must confirm
                          // via suggestions before Search is allowed.
                          selectedFromStation = null;
                          selectedToStation = null;
                        });
                      }
                    },
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _fromDebounce?.cancel();
    _toDebounce?.cancel();
    fromController.dispose();
    toController.dispose();
    // FIX #6 — Dispose FocusNodes.
    _fromFocus.dispose();
    _toFocus.dispose();
    _swapController.dispose();
    super.dispose();
  }
}
