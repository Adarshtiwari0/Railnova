import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/navigation/smooth_route.dart';
import '../../core/theme/skin_tokens.dart';
import '../../core/widgets/shimmer_box.dart';
import '../../core/widgets/tilt_3d.dart';
import '../../models/station.dart';
import '../../models/train_model.dart';
import '../../providers/theme_provider.dart';
import '../../services/station_service.dart';
import '../../services/train_service.dart';
import '../live/live_train_screen.dart';
import '../train_details/train_details_screen.dart';

enum _SortBy { expected, departure, delay }

class TrainListScreen extends StatefulWidget {
  final String fromCode;
  final String toCode;
  final String fromName;
  final String toName;

  /// Date to search on, carried over from the search screen's date picker.
  /// Defaults to today when not provided.
  final DateTime? initialDate;

  const TrainListScreen({
    super.key,
    required this.fromCode,
    required this.toCode,
    required this.fromName,
    required this.toName,
    this.initialDate,
  });

  @override
  State<TrainListScreen> createState() => _TrainListScreenState();
}

class _TrainListScreenState extends State<TrainListScreen> {
  final TrainService _trainService = TrainService();

  bool _isLoading = true;
  bool _hasError = false;

  String _errorMessage = "";

  List<Train> _trains = [];

  late DateTime _selectedDate;
  late String _journeyDate;

  // Mutable copies of the route endpoints — the header's X buttons let the
  // person swap either station without leaving this screen.
  late String _fromCode;
  late String _toCode;
  late String _fromName;
  late String _toName;

  // Inline station re-picker state (only one side open at a time).
  bool _pickingFrom = false;
  bool _pickingTo = false;
  final TextEditingController _pickController = TextEditingController();
  List<Station> _pickSuggestions = [];
  Timer? _pickDebounce;

  // Filters — null means "no filter applied" for that category.
  String? _typeFilter;
  String? _timeSlotFilter;
  _SortBy _sortBy = _SortBy.expected;
  bool _showAllSchedules = false;

  static const List<String> _timeSlots = [
    "Morning",
    "Afternoon",
    "Evening",
    "Night",
  ];

  /// Buckets a "HH:mm" departure time into a coarse slot for filtering.
  String? _timeSlotOf(String? departureTime) {
    if (departureTime == null) return null;
    final parts = departureTime.split(":");
    if (parts.isEmpty) return null;
    final hour = int.tryParse(parts[0]);
    if (hour == null) return null;

    if (hour >= 4 && hour < 12) return "Morning";
    if (hour >= 12 && hour < 17) return "Afternoon";
    if (hour >= 17 && hour < 21) return "Evening";
    return "Night";
  }

  /// Train types actually present in this search's results — filter chips
  /// are built from real data instead of a guessed fixed list, since
  /// RailRadar's `type` field varies (e.g. "RAJDHANI", "SF", "MAIL").
  List<String> get _availableTypes {
    final types = _trains
        .map((t) => t.type.trim())
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList();
    types.sort();
    return types;
  }

  List<Train> get _filteredTrains {
    final list = _trains.where((t) {
      if (_typeFilter != null && t.type.trim() != _typeFilter) return false;
      if (_timeSlotFilter != null &&
          _timeSlotOf(t.departureTime) != _timeSlotFilter) {
        return false;
      }
      return true;
    }).toList();

    DateTime? expectedOf(Train t) {
      if (t.liveEventTime != null) {
        try {
          return DateTime.parse(t.liveEventTime!).toLocal();
        } catch (_) {}
      }
      return t.scheduledDepartureDateTime(_selectedDate);
    }

    switch (_sortBy) {
      case _SortBy.expected:
        list.sort((a, b) {
          final ea = expectedOf(a);
          final eb = expectedOf(b);
          if (ea == null && eb == null) return 0;
          if (ea == null) return 1;
          if (eb == null) return -1;
          return ea.compareTo(eb);
        });
      case _SortBy.departure:
        list.sort((a, b) {
          final da = a.scheduledDepartureDateTime(_selectedDate);
          final db = b.scheduledDepartureDateTime(_selectedDate);
          if (da == null && db == null) return 0;
          if (da == null) return 1;
          if (db == null) return -1;
          return da.compareTo(db);
        });
      case _SortBy.delay:
        list.sort((a, b) {
          final da = int.tryParse(a.liveDelayMinutes ?? "");
          final db = int.tryParse(b.liveDelayMinutes ?? "");
          if (da == null && db == null) return 0;
          if (da == null) return 1;
          if (db == null) return -1;
          return db.compareTo(da); // most delayed first
        });
    }

    return list;
  }

  @override
  void initState() {
    super.initState();

    _fromCode = widget.fromCode;
    _toCode = widget.toCode;
    _fromName = widget.fromName;
    _toName = widget.toName;

    _selectedDate = widget.initialDate ?? DateTime.now();
    _journeyDate = DateFormat("yyyy-MM-dd").format(_selectedDate);

    _loadTrains();
  }

  @override
  void dispose() {
    _pickDebounce?.cancel();
    _pickController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime(2035),
    );

    if (picked == null) return;

    setState(() {
      _selectedDate = picked;
      _journeyDate = DateFormat("yyyy-MM-dd").format(picked);
      _showAllSchedules = false;
    });

    await _loadTrains(resetFilters: true);
  }

  // ============================================================
  // Header station swap — the X buttons
  // ============================================================

  void _clearFromStation() {
    setState(() {
      _fromCode = "";
      _fromName = "";
      _pickingFrom = true;
      _pickingTo = false;
      _pickController.clear();
      _pickSuggestions = [];
      _trains = [];
    });
  }

  void _clearToStation() {
    setState(() {
      _toCode = "";
      _toName = "";
      _pickingTo = true;
      _pickingFrom = false;
      _pickController.clear();
      _pickSuggestions = [];
      _trains = [];
    });
  }

  void _onPickQueryChanged(String query) {
    _pickDebounce?.cancel();
    if (query.trim().isEmpty) {
      setState(() => _pickSuggestions = []);
      return;
    }
    _pickDebounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final results = await StationService.searchStations(query.trim());
        if (!mounted) return;
        setState(() => _pickSuggestions = results);
      } catch (_) {
        // Silent — autocomplete only.
      }
    });
  }

  void _applyPickedStation(Station station) {
    setState(() {
      if (_pickingFrom) {
        _fromCode = station.code;
        _fromName = station.name;
        _pickingFrom = false;
      } else if (_pickingTo) {
        _toCode = station.code;
        _toName = station.name;
        _pickingTo = false;
      }
      _pickSuggestions = [];
      _pickController.clear();
    });
    FocusScope.of(context).unfocus();

    if (_fromCode.isNotEmpty && _toCode.isNotEmpty) {
      _loadTrains(resetFilters: true);
    }
  }

  Future<void> _loadTrains({bool resetFilters = false}) async {
    if (_fromCode.isEmpty || _toCode.isEmpty) return;

    setState(() {
      _isLoading = true;
      _hasError = false;
      _errorMessage = "";
    });

    try {
      // live: true enriches each train with its current delay/platform at
      // the `from` station — worth the extra upstream cost here since this
      // is the screen where that context matters most.
      final result = await _trainService.searchTrains(
        _fromCode,
        _toCode,
        _showAllSchedules ? null : _journeyDate,
        // A date-less timetable can include trains that are not running
        // today, so do not attach a potentially misleading live snapshot.
        live: !_showAllSchedules,
      );

      if (!mounted) return;

      setState(() {
        _trains = result;
        if (resetFilters) {
          _typeFilter = null;
          _timeSlotFilter = null;
        }
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

  Future<void> _refresh() async {
    await _loadTrains();
  }

  Future<void> _toggleScheduleScope() async {
    setState(() => _showAllSchedules = !_showAllSchedules);
    await _loadTrains(resetFilters: true);
  }

  @override
  Widget build(BuildContext context) {
    final skin = SkinTokens.of(context.watch<ThemeProvider>().skin);

    return Scaffold(
      backgroundColor: skin.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            if (!_isLoading && !_hasError && _trains.isNotEmpty) ...[
              _buildSortBar(),
              _buildFilterBar(),
            ],
            Expanded(
              child: _fromCode.isEmpty || _toCode.isEmpty
                  ? _buildPickPrompt()
                  : _isLoading
                  ? _buildLoadingState()
                  : _hasError
                  ? _buildErrorState()
                  : _buildTrainList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPickPrompt() {
    final skin = SkinTokens.of(context.watch<ThemeProvider>().skin);
    return Center(
      child: Text(
        "Pick a station above to continue",
        style: TextStyle(color: skin.dim),
      ),
    );
  }

  // ============================================================
  // Compact header — origin/destination with working X buttons
  // ============================================================

  Widget _buildHeader(BuildContext context) {
    final skin = SkinTokens.of(context.watch<ThemeProvider>().skin);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [skin.primaryDeep, skin.primary],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                visualDensity: VisualDensity.compact,
              ),
              const Expanded(
                child: Text(
                  "Available Trains",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                onPressed: _isLoading ? null : _pickDate,
                icon: const Icon(
                  Icons.calendar_month,
                  color: Colors.white,
                  size: 20,
                ),
                visualDensity: VisualDensity.compact,
                tooltip: DateFormat("dd MMM yyyy").format(_selectedDate),
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white),
                onSelected: (v) {
                  if (v == "refresh") _refresh();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: "refresh", child: Text("Refresh")),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Compact vertical route indicator: filled circle -> dotted
                // line -> pin, matching the from/to rows beside it.
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Column(
                    children: [
                      const Icon(Icons.circle, size: 9, color: Colors.white),
                      SizedBox(
                        height: 30,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: List.generate(
                            4,
                            (_) => Container(
                              width: 2,
                              height: 3,
                              color: Colors.white54,
                            ),
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.location_on,
                        size: 13,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _stationRow(
                        code: _fromCode,
                        name: _fromName,
                        picking: _pickingFrom,
                        onClear: _clearFromStation,
                      ),
                      const SizedBox(height: 14),
                      _stationRow(
                        code: _toCode,
                        name: _toName,
                        picking: _pickingTo,
                        onClear: _clearToStation,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_pickingFrom || _pickingTo) ...[
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _pickController,
                    autofocus: true,
                    onChanged: _onPickQueryChanged,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: _pickingFrom
                          ? "Search origin station"
                          : "Search destination station",
                      prefixIcon: const Icon(Icons.search, size: 18),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 10,
                      ),
                    ),
                  ),
                  if (_pickSuggestions.isNotEmpty)
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 180),
                      child: Material(
                        color: Colors.transparent,
                        child: ListView.builder(
                          shrinkWrap: true,
                          padding: EdgeInsets.zero,
                          itemCount: _pickSuggestions.length,
                          itemBuilder: (context, i) {
                            final s = _pickSuggestions[i];
                            return ListTile(
                              dense: true,
                              leading: Text(
                                s.code,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                              title: Text(
                                s.name,
                                style: const TextStyle(fontSize: 13.5),
                              ),
                              onTap: () => _applyPickedStation(s),
                            );
                          },
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stationRow({
    required String code,
    required String name,
    required bool picking,
    required VoidCallback onClear,
  }) {
    return Row(
      children: [
        Expanded(
          child: picking
              ? const Text(
                  "Choose a station below",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                  ),
                )
              : Text(
                  name.isEmpty ? "--" : name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
        ),
        if (!picking)
          InkWell(
            onTap: onClear,
            borderRadius: BorderRadius.circular(20),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.close, color: Colors.white70, size: 16),
            ),
          ),
      ],
    );
  }

  // ============================================================
  // Sort bar — sorts the real result list, not just a UI toggle
  // ============================================================

  Widget _buildSortBar() {
    final skin = SkinTokens.of(context.watch<ThemeProvider>().skin);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: [
          Text("Sort by:", style: TextStyle(fontSize: 13, color: skin.dim)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: skin.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: skin.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<_SortBy>(
                value: _sortBy,
                isDense: true,
                icon: Icon(
                  Icons.keyboard_arrow_down,
                  size: 18,
                  color: skin.dim,
                ),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: skin.text,
                ),
                dropdownColor: skin.card,
                items: const [
                  DropdownMenuItem(
                    value: _SortBy.expected,
                    child: Text("Expected time"),
                  ),
                  DropdownMenuItem(
                    value: _SortBy.departure,
                    child: Text("Departure time"),
                  ),
                  DropdownMenuItem(value: _SortBy.delay, child: Text("Delay")),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _sortBy = v);
                },
              ),
            ),
          ),
          const Spacer(),
          Text(
            "${_filteredTrains.length} of ${_trains.length} trains",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: skin.dim,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingState() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 6,
      itemBuilder: (context, index) => const TrainCardSkeleton(),
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
            const SizedBox(height: 20),
            Text(
              "Something went wrong",
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: skin.text,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _errorMessage,
              textAlign: TextAlign.center,
              style: TextStyle(color: skin.dim),
            ),
            const SizedBox(height: 25),
            ElevatedButton.icon(
              style: skin.primaryButtonStyle,
              onPressed: _loadTrains,
              icon: const Icon(Icons.refresh),
              label: const Text("Retry"),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    final skin = SkinTokens.of(context.watch<ThemeProvider>().skin);
    final types = _availableTypes;

    return Container(
      height: 44,
      margin: const EdgeInsets.only(top: 8),
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _filterChip(
            label: "All schedules",
            selected: _showAllSchedules,
            onTap: _isLoading ? null : _toggleScheduleScope,
          ),
          const SizedBox(width: 8),
          Container(width: 1, height: 22, color: skin.border),
          const SizedBox(width: 8),
          for (final slot in _timeSlots) ...[
            _filterChip(
              label: slot,
              selected: _timeSlotFilter == slot,
              onTap: () => setState(() {
                _timeSlotFilter = _timeSlotFilter == slot ? null : slot;
              }),
            ),
            const SizedBox(width: 8),
          ],
          if (types.isNotEmpty) ...[
            Container(
              width: 1,
              color: skin.border,
              margin: const EdgeInsets.symmetric(horizontal: 4),
            ),
            const SizedBox(width: 8),
            for (final type in types) ...[
              _filterChip(
                label: type,
                selected: _typeFilter == type,
                onTap: () => setState(() {
                  _typeFilter = _typeFilter == type ? null : type;
                }),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ],
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool selected,
    VoidCallback? onTap,
  }) {
    final skin = SkinTokens.of(context.watch<ThemeProvider>().skin);

    return Opacity(
      opacity: onTap == null ? 0.55 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? skin.primary : skin.card,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: selected ? skin.primary : skin.border),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : skin.text,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTrainList() {
    final trains = _filteredTrains;
    final skin = SkinTokens.of(context.watch<ThemeProvider>().skin);

    if (trains.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.train_outlined, size: 70, color: skin.dim),
              const SizedBox(height: 16),
              Text(
                _trains.isEmpty
                    ? "No trains found"
                    : "No trains match these filters",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: skin.text,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _trains.isEmpty
                    ? "Try a different date or route"
                    : "Try clearing a filter above",
                style: TextStyle(color: skin.dim),
              ),
              if (_trains.isNotEmpty &&
                  (_typeFilter != null || _timeSlotFilter != null)) ...[
                const SizedBox(height: 14),
                TextButton(
                  onPressed: () => setState(() {
                    _typeFilter = null;
                    _timeSlotFilter = null;
                  }),
                  child: const Text("Clear filters"),
                ),
              ],
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        itemCount: trains.length,
        itemBuilder: (context, index) {
          final train = trains[index];
          return _trainCard(train);
        },
      ),
    );
  }

  /// Formats an ISO datetime (e.g. "2026-07-28T20:57:00+05:30") as
  /// "08:57 PM" in the device's local time.
  String _fmtIso(String? iso) {
    if (iso == null) return "--";
    try {
      return DateFormat("hh:mm a").format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return "--";
    }
  }

  /// Formats a "HH:mm" 24-hour schedule time (e.g. "18:00") as "06:00 PM".
  String _fmtScheduled(String? time) {
    if (time == null) return "--";
    try {
      return DateFormat("hh:mm a").format(DateFormat("HH:mm").parse(time));
    } catch (_) {
      return time;
    }
  }

  /// Same as [_fmtScheduled] but folds in a known delay (in minutes) —
  /// e.g. scheduled "04:40" + 173 min delay = "07:33 AM", not "04:40 AM".
  /// Correctly rolls over past midnight since it operates on a real
  /// [DateTime], not raw string math. Used when RailRadar hasn't confirmed
  /// an exact actual-departure timestamp but has given a delay figure.
  String _fmtScheduledWithDelay(String? time, int? delayMinutes) {
    if (time == null) return "--";
    try {
      final base = DateFormat("HH:mm").parse(time);
      final withDelay = delayMinutes != null && delayMinutes != 0
          ? base.add(Duration(minutes: delayMinutes))
          : base;
      return DateFormat("hh:mm a").format(withDelay);
    } catch (_) {
      return _fmtScheduled(time);
    }
  }

  /// A thin dashed line used between the origin/destination names — plain
  /// [Divider]s render solid, so this fakes the dotted look with small
  /// evenly-spaced boxes instead of pulling in a dependency for it.
  Widget _dashedLine(Color color) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const dashWidth = 4.0;
        const gap = 3.0;
        final count = (constraints.maxWidth / (dashWidth + gap)).floor();
        return SizedBox(
          height: 1,
          child: Row(
            children: List.generate(
              count.clamp(0, 200),
              (_) => Padding(
                padding: const EdgeInsets.only(right: gap),
                child: Container(width: dashWidth, height: 1, color: color),
              ),
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // Compact train card
  // ============================================================

  Widget _trainCard(Train train) {
    final skin = SkinTokens.of(context.watch<ThemeProvider>().skin);

    // Scheduled vs expected time, with midnight-safe delay math handled by
    // Train.scheduledDepartureDateTime / _fmtScheduledWithDelay (both work
    // off real DateTime objects, not raw string comparisons).
    final scheduledText = _fmtScheduled(train.departureTime);
    final delayMin = int.tryParse(train.liveDelayMinutes ?? "");

    final String expectedText;
    if (train.liveEventTime != null) {
      expectedText = _fmtIso(train.liveEventTime);
    } else if (delayMin != null && delayMin != 0) {
      expectedText = _fmtScheduledWithDelay(train.departureTime, delayMin);
    } else {
      expectedText = scheduledText;
    }

    final bool showTwoTimes = expectedText != scheduledText;

    return Tilt3D(
      borderRadius: BorderRadius.circular(16),
      child: Card(
        color: skin.card,
        margin: const EdgeInsets.only(bottom: 12),
        elevation: 2,
        shadowColor: Colors.black12,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openDetails(train),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Train number chip + name + a compact live-tracking action.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: skin.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              train.trainNumber,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: skin.primaryDeep,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            train.trainName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: skin.text,
                              fontFamily: skin.fontFamily,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => _openLiveStatus(train),
                      icon: Icon(
                        Icons.my_location,
                        size: 18,
                        color: skin.primary,
                      ),
                      tooltip: "Live status",
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Origin ........ Destination
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        train.from,
                        style: TextStyle(fontSize: 11.5, color: skin.dim),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(child: _dashedLine(skin.border)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        train.to,
                        style: TextStyle(fontSize: 11.5, color: skin.dim),
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 10),

                // Scheduled time  |  Expected/current time + platform.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            scheduledText,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: showTwoTimes ? skin.dim : skin.text,
                              decoration: showTwoTimes
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if (showTwoTimes)
                            Text(
                              expectedText,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: train.isEarly
                                    ? Colors.green.shade700
                                    : (train.isDelayed
                                          ? Colors.red.shade700
                                          : skin.text),
                              ),
                            ),
                          if (train.livePlatform != null) ...[
                            const SizedBox(height: 3),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: skin.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                "PF ${train.livePlatform}",
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: skin.primaryDeep,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),
                _statusBadge(train, skin),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Delayed / On time / Early / Unknown — always from real data, never
  /// assumed. A missing `live` block shows a neutral "Live status
  /// unavailable" chip instead of silently implying on-time.
  Widget _statusBadge(Train train, SkinTokens skin) {
    late final Color bg;
    late final Color fg;
    late final IconData icon;
    late final String label;

    if (!train.hasLiveDelayData) {
      bg = skin.bg;
      fg = skin.dim;
      icon = Icons.info_outline;
      label = "Live status unavailable";
    } else if (train.isDelayed) {
      bg = Colors.red.shade50;
      fg = Colors.red.shade700;
      icon = Icons.error_outline;
      label = "Delayed by ${train.formattedLiveDelay}";
    } else if (train.isEarly) {
      bg = Colors.green.shade50;
      fg = Colors.green.shade700;
      icon = Icons.trending_up;
      label = "Early by ${train.formattedEarlyBy}";
    } else {
      bg = Colors.green.shade50;
      fg = Colors.green.shade700;
      icon = Icons.check_circle_outline;
      label = "On time";
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  void _openDetails(Train train) {
    Navigator.push(
      context,
      SmoothRoute(
        page: TrainDetailsScreen(
          trainNumber: train.trainNumber,
          trainName: train.trainName,
        ),
      ),
    );
  }

  void _openLiveStatus(Train train) {
    Navigator.push(
      context,
      SmoothRoute(page: LiveTrainScreen(initialTrainNumber: train.trainNumber)),
    );
  }
}
