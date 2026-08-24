import 'dart:async';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/skin_tokens.dart';
import '../../core/utils/format.dart';
import '../../core/widgets/train_loading_animation.dart';
import '../../core/widgets/vertical_route_timeline.dart';
import '../../providers/theme_provider.dart';
import '../../services/notification_service.dart';

class LiveTrainScreen extends StatefulWidget {
  /// When provided (e.g. tapped "Live Status" from a train card or details
  /// screen), the field is pre-filled and the live status is fetched
  /// immediately instead of waiting for the user to type a number.
  final String? initialTrainNumber;

  const LiveTrainScreen({super.key, this.initialTrainNumber});

  @override
  State<LiveTrainScreen> createState() => _LiveTrainScreenState();
}

class _LiveTrainScreenState extends State<LiveTrainScreen> {
  final TextEditingController trainController = TextEditingController();
  Map<String, dynamic>? trainData;
  bool isLoading = false;
  List<Map<String, String>> favoriteTrains = [];

  List<Map<String, String>> recentSearches = [];

  bool isFavorite = false;

  /// Drives the floating "distance + delay" popup on the route timeline —
  /// bumped on every successful fetch so the timeline knows to show it,
  /// and auto-hidden a few seconds later.
  int _popupTick = 0;

  /// Which journey to show — `null` = today (RailRadar auto-detects the
  /// most recent journey). Any other date shows that specific journey
  /// (yesterday, tomorrow, or a custom date from the calendar).
  DateTime? _selectedDate;

  bool get _isToday =>
      _selectedDate == null || _isSameDay(_selectedDate!, DateTime.now());

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// The exact date (YYYY-MM-DD) sent to the API when [_selectedDate] is
  /// set. Null when showing today, so the API auto-detects.
  String? get _selectedDateParam {
    if (_selectedDate == null) return null;
    final d = _selectedDate!;
    return "${d.year.toString().padLeft(4, '0')}-"
        "${d.month.toString().padLeft(2, '0')}-"
        "${d.day.toString().padLeft(2, '0')}";
  }

  /// Short label for the date-picker button — "Today", "Yesterday",
  /// "Tomorrow", or the actual date for anything further out.
  String get _selectedDateLabel {
    if (_selectedDate == null) return "Today";
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    final tomorrow = now.add(const Duration(days: 1));
    if (_isSameDay(_selectedDate!, now)) return "Today";
    if (_isSameDay(_selectedDate!, yesterday)) return "Yesterday";
    if (_isSameDay(_selectedDate!, tomorrow)) return "Tomorrow";
    return DateFormat('dd MMM').format(_selectedDate!);
  }

  void _setSelectedDate(DateTime? date) {
    if (_selectedDate == date) return;
    setState(() => _selectedDate = date);
    getLiveTrain();
  }

  /// Bottom-sheet date picker — Yesterday / Today / Tomorrow / a full
  /// calendar / Cancel, matching the familiar "Choose the date" pattern.
  Future<void> _openDatePicker() async {
    final now = DateTime.now();
    final skin = SkinTokens.of(context.read<ThemeProvider>().skin);

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: skin.card,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        child: Column(
                          children: [
                            const Text(
                              "Choose the date",
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              "for train ${trainController.text.trim()}",
                              style: TextStyle(
                                fontSize: 12,
                                color: skin.dim,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      _sheetOption("Yesterday", () {
                        Navigator.pop(context);
                        _setSelectedDate(now.subtract(const Duration(days: 1)));
                      }),
                      const Divider(height: 1),
                      _sheetOption("Today", () {
                        Navigator.pop(context);
                        _setSelectedDate(null);
                      }),
                      const Divider(height: 1),
                      _sheetOption("Tomorrow", () {
                        Navigator.pop(context);
                        _setSelectedDate(now.add(const Duration(days: 1)));
                      }),
                      const Divider(height: 1),
                      _sheetOption("Choose from Calendar", () async {
                        Navigator.pop(context);
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _selectedDate ?? now,
                          firstDate: now.subtract(const Duration(days: 2)),
                          lastDate: now.add(const Duration(days: 4)),
                        );
                        if (picked != null) _setSelectedDate(picked);
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: skin.card,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: _sheetOption(
                    "Cancel",
                    () => Navigator.pop(context),
                    bold: true,
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _sheetOption(String label, VoidCallback onTap, {bool bold = false}) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 16.5,
              color: Colors.blue.shade600,
              fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  /// Debounced search-as-you-type against our local `trains` table — never
  /// touches RailRadar directly (see routes/train.js -> lookupTrains).
  void _onTrainQueryChanged(String query) {
    setState(() {}); // keep the clear/search suffix icon in sync

    _suggestDebounce?.cancel();

    if (query.trim().isEmpty) {
      setState(() {
        _trainSuggestions = [];
        _suggestionsVisible = false;
      });
      return;
    }

    _suggestDebounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final uri = Uri.parse(
          "${AppConfig.baseUrl}/trains/lookup",
        ).replace(queryParameters: {"q": query.trim()});

        final response = await http.get(uri);
        if (!mounted || response.statusCode != 200) return;

        final body = jsonDecode(response.body);
        final List results = body["data"] ?? [];

        setState(() {
          _trainSuggestions = results.cast<Map<String, dynamic>>();
          _suggestionsVisible = _trainSuggestions.isNotEmpty;
        });
      } catch (_) {
        // Silent — this is just autocomplete, the main search button still
        // works even if suggestions fail to load.
      }
    });
  }

  void _selectTrainSuggestion(Map<String, dynamic> suggestion) {
    final number = suggestion["number"].toString();
    final name = suggestion["name"]?.toString();
    trainController.text = name != null && name.isNotEmpty
        ? "$number · $name"
        : number;
    setState(() {
      _suggestionsVisible = false;
      _trainSuggestions = [];
    });
    FocusScope.of(context).unfocus();
    getLiveTrain();
  }

  Timer? _autoRefreshTimer;
  Timer? _suggestDebounce;
  List<Map<String, dynamic>> _trainSuggestions = [];
  bool _suggestionsVisible = false;

  /// RailRadar's `/trains/{number}/live` endpoint sets the top-level
  /// `status` to "cancelled" when the whole journey is cancelled for the
  /// day. A cancelled train still returns schedule data, so we surface it
  /// as a badge rather than blocking the rest of the screen.
  bool get _isTrainCancelled {
    return trainData?["status"]?.toString().toLowerCase() == "cancelled";
  }

  /// True when the train's journey for the selected date hasn't begun —
  /// used so the "Delayed / Running on time" chip doesn't show for a train
  /// that hasn't even left its origin station yet.
  bool get _isNotStarted {
    final status = trainData?["status"]?.toString().toLowerCase() ?? "";
    return status.contains("not") ||
        status.contains("scheduled") ||
        status.contains("upcoming");
  }

  /// "Starts in 2h 15m" — derived from the origin station's scheduled
  /// departure, only while [_isNotStarted]. Refreshes for free whenever the
  /// screen rebuilds (e.g. the existing 30s auto-refresh for today's
  /// trains) — no separate timer needed.
  String? get _startsInLabel {
    if (!_isNotStarted || trainData == null) return null;
    final route = (trainData!["route"] as List?)?.cast<Map<String, dynamic>>();
    final dep = route?.isNotEmpty == true
        ? route!.first["scheduledDeparture"]
        : null;
    if (dep == null) return null;

    try {
      final diff = DateTime.parse(dep).toLocal().difference(DateTime.now());
      if (diff.isNegative) return null;
      final h = diff.inHours;
      final m = diff.inMinutes % 60;
      return h > 0 ? "Starts in ${h}h ${m}m" : "Starts in ${m}m";
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();

    loadFavorites();
    loadRecentSearches();

    if (widget.initialTrainNumber != null &&
        widget.initialTrainNumber!.trim().isNotEmpty) {
      trainController.text = widget.initialTrainNumber!.trim();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        getLiveTrain();
      });
    }
  }

  /// Re-fetches the currently loaded train's live status every 30s. Only
  /// runs while a train is actually loaded — no point polling before a
  /// search, and it's cancelled on dispose so it never fires after the
  /// screen is gone.
  void _startAutoRefresh() {
    _autoRefreshTimer?.cancel();

    if (!_isToday) return; // Past/future journey — data won't change.

    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted || trainController.text.trim().isEmpty) return;
      getLiveTrain(silent: true);
    });
  }

  Future<void> loadRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();

    final data = prefs.getString("recent_train_number_searches");
    if (data == null) return;

    try {
      final List decoded = jsonDecode(data);
      final loaded = decoded.map((e) => Map<String, String>.from(e)).toList();
      if (mounted) setState(() => recentSearches = loaded);
    } catch (_) {
      // Corrupt stored data — drop it so it can't keep throwing on every load.
      await prefs.remove("recent_train_number_searches");
    }
  }

  Future<void> saveRecentSearch(String trainNo, String trainName) async {
    final prefs = await SharedPreferences.getInstance();

    recentSearches.removeWhere((e) => e["number"] == trainNo);

    recentSearches.insert(0, {"number": trainNo, "name": trainName});

    if (recentSearches.length > 10) {
      recentSearches = recentSearches.sublist(0, 10);
    }

    await prefs.setString(
      "recent_train_number_searches",
      jsonEncode(recentSearches),
    );

    if (mounted) setState(() {});
  }

  Future<void> loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();

    final data = prefs.getString("favorite_trains");
    if (data == null) return;

    try {
      final List decoded = jsonDecode(data);
      final loaded = decoded.map((e) => Map<String, String>.from(e)).toList();
      if (mounted) setState(() => favoriteTrains = loaded);
    } catch (_) {
      // Corrupt stored data — drop it so it can't keep throwing on every load.
      await prefs.remove("favorite_trains");
    }
  }

  Future<void> toggleFavorite() async {
    if (trainData == null) return;

    final prefs = await SharedPreferences.getInstance();

    final trainNo = trainData!["train"]["number"].toString();
    final trainName = trainData!["train"]["name"].toString();

    final index = favoriteTrains.indexWhere((e) => e["number"] == trainNo);

    setState(() {
      if (index != -1) {
        favoriteTrains.removeAt(index);
        isFavorite = false;
      } else {
        favoriteTrains.add({"number": trainNo, "name": trainName});
        isFavorite = true;
      }
    });

    await prefs.setString("favorite_trains", jsonEncode(favoriteTrains));

    if (index != -1) {
      await NotificationService.unsubscribeFromTrain(trainNo);
    } else {
      await NotificationService.subscribeToTrain(
        trainNumber: trainNo,
        trainName: trainName,
      );
    }
  }

  /// Formats a delay in minutes as "Xh Ym" once it crosses 60 minutes,
  /// instead of showing a raw minute count like "88 min".
  String _formatDelay(int minutes) => formatDelay(minutes);

  /// Builds a short, shareable text summary of the currently loaded train's
  /// live status (e.g. for sending to family over WhatsApp) and opens the
  /// platform share sheet.
  Future<void> _shareLiveStatus() async {
    if (trainData == null) return;

    final train = trainData!["train"] ?? {};
    final number = train["number"]?.toString() ?? "";
    final name = train["name"]?.toString() ?? "";
    final source = train["source"]?["name"]?.toString() ?? "";
    final destination = train["destination"]?["name"]?.toString() ?? "";

    final delay =
        int.tryParse(trainData!["delayMinutes"]?.toString() ?? "") ?? 0;
    final statusLine = _isTrainCancelled
        ? "❌ Cancelled today"
        : delay > 0
        ? "⏰ Running late by ${_formatDelay(delay)}"
        : "✅ Running on time";

    final currentStation =
        trainData!["currentLocation"]?["stationName"]?.toString() ??
        trainData!["previousHalt"]?["stationName"]?.toString();

    final buffer = StringBuffer()
      ..writeln("🚆 $name ($number)")
      ..writeln(statusLine);

    if (currentStation != null) buffer.writeln("📍 Near $currentStation");
    if (source.isNotEmpty && destination.isNotEmpty) {
      buffer.writeln("$source → $destination");
    }

    buffer.write("\nTracked live on RailNova");

    await SharePlus.instance.share(ShareParams(text: buffer.toString()));
  }

  /// The search field can show "20843 · Bhagat Ki Kothi SF Express" after a
  /// name-search pick — this pulls out just the leading digits, which is
  /// what the API actually needs. Falls back to the raw trimmed text when
  /// the person typed a number directly (no " · " suffix).
  String _activeTrainNumber() {
    final text = trainController.text.trim();
    final match = RegExp(r'^\d{1,5}').firstMatch(text);
    return match?.group(0) ?? text;
  }

  /// Bumped on every call so a slow/out-of-order response can tell it's
  /// stale (e.g. tapping "Yesterday" then quickly "Today" — if the
  /// "Yesterday" request happens to land after the "Today" one, it must
  /// NOT be allowed to overwrite the newer data on screen).
  int _requestSeq = 0;

  Future<void> getLiveTrain({bool silent = false}) async {
    if (!silent) setState(() => isLoading = true);

    final int mySeq = ++_requestSeq;
    final trainNumber = _activeTrainNumber();
    final String? requestedDateParam = _selectedDateParam;
    final url =
        Uri.parse(
          "${AppConfig.baseUrl}/trains/live/${Uri.encodeComponent(trainNumber)}",
        ).replace(
          queryParameters: requestedDateParam != null
              ? {"date": requestedDateParam}
              : null,
        );

    try {
      final response = await http.get(url).timeout(
        AppConfig.apiTimeout,
        onTimeout: () => throw Exception(
          "Request timed out — the server may be waking up. Please try again.",
        ),
      );

      // A newer request (different date/train, or a fresher refresh) has
      // since been fired — discard this now-stale response instead of
      // clobbering whatever is currently on screen.
      if (mySeq != _requestSeq) return;

      if (response.statusCode == 200) {
        if (!mounted) return;

        final json = jsonDecode(response.body);
        final data = json["data"]?["data"];

        setState(() {
          trainData = data;
          isFavorite = favoriteTrains.any((e) => e["number"] == trainNumber);
          _popupTick++;
        });

        // Only start polling after a successful load — no point refreshing
        // a train that isn't actually loaded. Start it before the (awaited)
        // recent-search save so a missing "train" field can never stop it.
        _startAutoRefresh();

        final trainName = (data?["train"]?["name"] ?? "").toString();
        await saveRecentSearch(trainNumber, trainName);
      } else {
        if (!mounted) return;

        // Don't interrupt the user with a snackbar for a failed background
        // refresh — just leave the last-known data on screen and try again
        // on the next tick.
        if (silent) return;

        String message = "Unable to fetch live status (${response.statusCode})";
        try {
          final body = jsonDecode(response.body);
          if (body["message"] != null) message = body["message"];
        } catch (_) {}

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      if (!mounted || silent) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Network error: ${e.toString()}")));
    }

    if (mounted && !silent) setState(() => isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final skin = SkinTokens.of(context.watch<ThemeProvider>().skin);

    Map<String, dynamic>? currentStation;

    if (trainData != null) {
      final route = (trainData!["route"] as List?)?.cast<Map<String, dynamic>>();
      final loc = trainData!["currentLocation"] as Map<String, dynamic>?;
      if (route != null && loc != null) {
        currentStation = route.firstWhere(
          (station) => station["stationCode"] == loc["stationCode"],
          orElse: () => {},
        );
      }
    }

    return Stack(
      children: [
        Scaffold(
          backgroundColor: skin.bg,
          appBar: AppBar(
            elevation: 0,
            backgroundColor: skin.primary,
            centerTitle: false,
            titleSpacing: 8,
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.train_rounded, color: Colors.white),
                ),

                const SizedBox(width: 12),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        trainData != null
                            ? (trainData!["train"]?["number"]?.toString() ??
                                  "RailNova")
                            : "RailNova",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 20,
                          color: Colors.white,
                          fontFamily: skin.fontFamily,
                        ),
                      ),

                      Text(
                        trainData != null
                            ? (trainData!["train"]?["name"]?.toString() ?? "")
                            : "Live Train Tracking",
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white70,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                if (trainData != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.circle, size: 8, color: Colors.white),

                        SizedBox(width: 5),

                        Text(
                          "LIVE",
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            actions: [
              IconButton(
                onPressed: trainData == null ? null : _shareLiveStatus,
                icon: const Icon(Icons.share, color: Colors.white),
                tooltip: "Share live status",
              ),
              IconButton(
                onPressed: trainData == null ? null : toggleFavorite,
                icon: Icon(
                  isFavorite ? Icons.star : Icons.star_border,
                  color: Colors.amber,
                ),
                tooltip: "Mark this train as favorite",
              ),
            ],
          ),
          body: trainData == null
              ? _buildSearchState(skin)
              : Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                        child: _buildResultBody(skin, currentStation),
                      ),
                    ),
                    _buildBottomStatusBar(skin),
                  ],
                ),
        ),
      ],
    );
  }

  /// The pre-search state — enter a train number, pick a date, track it.
  Widget _buildSearchState(SkinTokens skin) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: skin.card,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .05),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              children: [
                TextField(
                  controller: trainController,
                  keyboardType: TextInputType.text,
                  textInputAction: TextInputAction.search,
                  onChanged: _onTrainQueryChanged,

                  onSubmitted: (_) async {
                    if (trainController.text.trim().isEmpty) return;
                    setState(() => _suggestionsVisible = false);
                    await getLiveTrain();
                  },
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    color: skin.text,
                  ),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: skin.bg,
                    hintText: "Enter Train Number or Name",
                    prefixIcon: Icon(Icons.train, color: skin.primary),
                    suffixIcon: trainController.text.isEmpty
                        ? Icon(Icons.search, color: skin.primary)
                        : IconButton(
                            icon: const Icon(Icons.clear, color: Colors.red),
                            onPressed: () {
                              setState(() {
                                trainController.clear();
                                trainData = null;
                                _trainSuggestions = [];
                                _suggestionsVisible = false;
                              });
                            },
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),

                if (_suggestionsVisible)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    constraints: const BoxConstraints(maxHeight: 260),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      clipBehavior: Clip.antiAlias,
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: _trainSuggestions.length,
                        separatorBuilder: (_, _) =>
                            Divider(height: 1, color: Colors.grey.shade200),
                        itemBuilder: (context, index) {
                          final s = _trainSuggestions[index];
                          return ListTile(
                            dense: true,
                            onTap: () => _selectTrainSuggestion(s),
                            leading: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: skin.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                s["number"]?.toString() ?? "",
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: skin.primaryDeep,
                                ),
                              ),
                            ),
                            title: Text(
                              s["name"]?.toString() ?? "",
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        },
                      ),
                    ),
                  ),

                const SizedBox(height: 18),

                GestureDetector(
                  onTap: _openDatePicker,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: skin.bg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: skin.border),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.event, color: skin.primary, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          _selectedDateLabel,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14.5,
                            color: skin.text,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          Icons.keyboard_arrow_down,
                          color: skin.dim,
                          size: 20,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 14),

                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: skin.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),

                    onPressed: () async {
                      if (trainController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Enter Train Number")),
                        );

                        return;
                      }

                      await getLiveTrain();
                    },

                    icon: const Icon(
                      Icons.location_searching,
                      color: Colors.white,
                    ),

                    label: Text(
                      isLoading
                          ? "Tracking..."
                          : _isToday
                          ? "Track Live Train"
                          : "Track $_selectedDateLabel's Journey",
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                if (trainData != null)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 52),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            side: BorderSide(color: skin.primary, width: 1.5),
                          ),

                          onPressed: isLoading
                              ? null
                              : () async {
                                  await getLiveTrain();
                                },

                          icon: isLoading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.refresh),

                          label: Text(
                            isLoading ? "Refreshing..." : "Refresh Live Status",
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),

                if (trainData != null) const SizedBox(height: 10),

                if (trainData != null)
                  Text(
                    "Pull latest train location anytime",
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          if (isLoading && trainData == null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [skin.primary, skin.primaryDeep],
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: const TrainLoadingAnimation(
                message: "Locating your train...",
              ),
            ),

          if (!isLoading && recentSearches.isNotEmpty)
            Card(
              color: skin.card,
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.history, color: skin.primary),
                        const SizedBox(width: 8),
                        Text(
                          "Recent Searches",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: skin.text,
                          ),
                        ),

                        const Spacer(),

                        TextButton(
                          onPressed: () async {
                            final prefs = await SharedPreferences.getInstance();

                            await prefs.remove("recent_train_number_searches");

                            setState(() {
                              recentSearches.clear();
                            });
                          },
                          child: const Text("Clear"),
                        ),
                      ],
                    ),

                    const Divider(),

                    ...recentSearches.map(
                      (train) => ListTile(
                        leading: Icon(Icons.train_rounded, color: skin.primary),

                        title: Text(
                          train["name"] ?? "",
                          style: TextStyle(color: skin.text),
                        ),

                        subtitle: Text(
                          train["number"] ?? "",
                          style: TextStyle(color: skin.dim),
                        ),

                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),

                        onTap: () async {
                          trainController.text = train["number"] ?? "";
                          await getLiveTrain();
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  /// Clean, "Where Is My Train"-style results view — a date/change-train
  /// row, the Arrival/Day/Departure header, then the route timeline
  /// itself. No extra summary cards; the timeline plus the sticky bottom
  /// bar carry all the live info.
  Widget _buildResultBody(
    SkinTokens skin,
    Map<String, dynamic>? currentStation,
  ) {
    final dayLabel = DateFormat(
      'MMM d, EEE',
    ).format(_selectedDate ?? DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            GestureDetector(
              onTap: _openDatePicker,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: skin.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _selectedDateLabel,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: skin.primaryDeep,
                        fontSize: 13.5,
                      ),
                    ),
                    Icon(
                      Icons.keyboard_arrow_down,
                      size: 18,
                      color: skin.primaryDeep,
                    ),
                  ],
                ),
              ),
            ),
            GestureDetector(
              onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Coach position isn't available yet"),
                ),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: skin.bg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: skin.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.event_seat, size: 15, color: skin.dim),
                    const SizedBox(width: 6),
                    Text(
                      "Coach position",
                      style: TextStyle(fontSize: 13, color: skin.dim),
                    ),
                  ],
                ),
              ),
            ),
            GestureDetector(
              onTap: () => setState(() {
                trainData = null;
                trainController.clear();
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: skin.bg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: skin.border),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.search, size: 15, color: skin.dim),
                    const SizedBox(width: 6),
                    Text(
                      "Search another train",
                      style: TextStyle(fontSize: 13, color: skin.dim),
                    ),
                  ],
                ),
              ),
            ),
            if (_isTrainCancelled)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.cancel_rounded,
                      size: 14,
                      color: Colors.red.shade700,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      "Cancelled",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.red.shade700,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),

        const SizedBox(height: 16),

        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: skin.bg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  "Arrival",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                    color: skin.text,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  "Day 1 - $dayLabel",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                    color: skin.text,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  "Departure",
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12.5,
                    color: skin.text,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 18),

        Builder(
          builder: (context) {
            final status = (trainData!["status"]?.toString() ?? "")
                .toLowerCase();
            final route = (trainData!["route"] as List)
                .cast<Map<String, dynamic>>();
            final last = route.isNotEmpty ? route.last : null;
            final loc = trainData!["currentLocation"] as Map<String, dynamic>?;

            final isCompleted =
                status.contains("complete") || status.contains("terminat");
            final isNotStarted =
                status.contains("not") ||
                status.contains("scheduled") ||
                status.contains("upcoming");

            String text;
            Color bg, fg;
            IconData icon;

            if (isNotStarted) {
              text = _startsInLabel != null
                  ? "Train has not started yet. ${_startsInLabel!}."
                  : "Train has not started yet.";
              bg = Colors.blueGrey.shade50;
              fg = Colors.blueGrey.shade700;
              icon = Icons.schedule;
            } else if (isCompleted && last != null) {
              final destName = last["stationName"]?.toString() ?? "";
              final arrivedAt =
                  last["actualArrival"] ?? last["actualDeparture"];
              String timeText = "";
              if (arrivedAt != null) {
                try {
                  timeText =
                      " at ${DateFormat("hh:mm a").format(DateTime.parse(arrivedAt).toLocal())}";
                } catch (_) {}
              }
              text = "Train reached $destName$timeText. Journey completed.";
              bg = Colors.green.shade50;
              fg = Colors.green.shade800;
              icon = Icons.check_circle;
            } else if (loc != null) {
              final currentIdx = route.indexWhere(
                (s) => s["sequence"] == loc["sequence"],
              );
              final currentName = currentIdx != -1
                  ? (route[currentIdx]["stationName"]?.toString() ?? "")
                  : "";
              if (currentName.isEmpty) return const SizedBox.shrink();
              text = "Train reached $currentName.";
              bg = skin.primary.withValues(alpha: 0.1);
              fg = skin.primaryDeep;
              icon = Icons.train_rounded;
            } else {
              return const SizedBox.shrink();
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(icon, color: fg, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        text,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: fg,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),

        VerticalRouteTimeline(
          route: (trainData!["route"] as List).cast<Map<String, dynamic>>(),
          currentLocation:
              trainData!["currentLocation"] as Map<String, dynamic>?,
          previousHalt: trainData!["previousHalt"] as Map<String, dynamic>?,
          nextHalt: trainData!["nextHalt"] as Map<String, dynamic>?,
          delayMinutes: int.tryParse(
            trainData!["delayMinutes"]?.toString() ?? "",
          ),
          popupTrigger: _popupTick,
          skin: skin,
          notStarted: _isNotStarted,
          startsInLabel: _startsInLabel,
        ),

        const SizedBox(height: 16),
      ],
    );
  }

  /// Persistent bar pinned to the bottom of the results screen — distance
  /// to the next halt, delay, last-updated text, and a manual refresh
  /// button. Always visible (unlike the timeline's brief popup).
  Widget _buildBottomStatusBar(SkinTokens skin) {
    if (trainData == null) return const SizedBox.shrink();

    final delay =
        int.tryParse(trainData!["delayMinutes"]?.toString() ?? "") ?? 0;
    final loc = trainData!["currentLocation"] as Map<String, dynamic>?;
    String? distanceLabel;

    if (loc != null) {
      final route = (trainData!["route"] as List?)
          ?.cast<Map<String, dynamic>>();
      final nextHalt = trainData!["nextHalt"] as Map<String, dynamic>?;
      final nextDist = (nextHalt?["distance"] as num?)?.toDouble();
      final nextName = nextHalt?["stationName"]?.toString();

      // Read the current position's own `distance` straight off `route`
      // (every station there carries one, not just previousHalt/nextHalt)
      // instead of interpolating from previousHalt via segmentProgress —
      // that interpolation overshoots badly when the train is currently
      // sitting well past previousHalt but the app doesn't know it.
      final currentIdx = route?.indexWhere(
        (s) => s["sequence"] == loc["sequence"],
      );
      final current = (currentIdx != null && currentIdx >= 0)
          ? route![currentIdx]
          : null;
      final currentDist = (current?["distance"] as num?)?.toDouble();

      if (currentDist != null && nextDist != null && nextName != null) {
        final remaining = nextDist - currentDist;
        if (remaining >= 0) {
          distanceLabel = "~${remaining.round()} km to $nextName";
        }
      }
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      decoration: BoxDecoration(
        color: skin.card,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (distanceLabel != null)
                    Text(
                      distanceLabel,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                        color: skin.text,
                      ),
                    ),
                  const SizedBox(height: 4),
                  if (_isNotStarted)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.blueGrey.shade50,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _startsInLabel ?? "Train not started yet",
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.blueGrey.shade700,
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: delay > 0
                            ? Colors.red.shade50
                            : Colors.green.shade50,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        delay > 0
                            ? "Delayed by ${_formatDelay(delay)}"
                            : "Running on time",
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: delay > 0
                              ? Colors.red.shade700
                              : Colors.green.shade700,
                        ),
                      ),
                    ),
                  const SizedBox(height: 3),
                  Text(
                    "Updated a few seconds ago",
                    style: TextStyle(fontSize: 11, color: skin.dim),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: isLoading ? null : () => getLiveTrain(),
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: skin.primary.withValues(alpha: 0.12),
                ),
                child: isLoading
                    ? Padding(
                        padding: const EdgeInsets.all(11),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: skin.primary,
                        ),
                      )
                    : Icon(Icons.refresh, color: skin.primary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _suggestDebounce?.cancel();
    trainController.dispose();
    super.dispose();
  }
}
