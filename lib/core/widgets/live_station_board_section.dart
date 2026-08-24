import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../config/app_config.dart';
import '../theme/skin_tokens.dart';
import '../../models/station.dart';
import '../../providers/theme_provider.dart';
import '../../services/station_service.dart';

/// "What else is happening at [station] right now" — pulled from
/// RailRadar's Station Live Board (`/stations/{code}/live`).
///
/// Fully independent of whatever train is being live-tracked elsewhere on
/// the page — it starts empty and only shows results once the person
/// searches for and picks a station themselves. Tapping a train in the
/// results immediately switches the main search to live-track that train
/// (via [onTrackTrain]).
class LiveStationBoardSection extends StatefulWidget {
  final void Function(String trainNumber)? onTrackTrain;

  /// When supplied, the board opens already pointed at this station and
  /// fetches straight away — the search already happened on Home, so asking
  /// for the same station name a second time would be pure friction.
  final String? initialStationCode;
  final String? initialStationName;

  const LiveStationBoardSection({
    super.key,
    this.onTrackTrain,
    this.initialStationCode,
    this.initialStationName,
  });

  @override
  State<LiveStationBoardSection> createState() =>
      _LiveStationBoardSectionState();
}

class _LiveStationBoardSectionState extends State<LiveStationBoardSection> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _destFilterController = TextEditingController();
  Timer? _destDebounce;
  List<Station> _destSuggestions = [];
  bool _destSuggestionsVisible = false;
  String? _destFilterCode;
  String? _destFilterName;
  // Train number -> that train's stop `sequence` at the filter station.
  // Keyed by sequence (not just presence) so we can tell *direction* apart
  // from a train that merely also touches the filter station on its way
  // back — see _filteredTrains below.
  Map<String, num>? _destTrainSequence;
  bool _destLoading = false;
  Timer? _debounce;
  List<Station> _suggestions = [];
  bool _suggestionsVisible = false;

  String? _selectedCode;
  String? _selectedName;

  bool _loading = false;
  String? _error;
  List<Map<String, dynamic>> _trains = [];

  /// Trains filtered by the optional "Going to" box — a train qualifies
  /// only if it also shows up on the *filter* station's own live board
  /// (fetched separately with `includeIntermediate=true`), AND its stop
  /// `sequence` at the filter station is *after* its sequence at the
  /// currently selected station. That catches trains that genuinely pass
  /// through the filter station on their way from here, not just any
  /// train that touches both stations — without the sequence check, a
  /// train running the opposite way (filter station -> here) also shows
  /// up here since it visits both stations too, just in reverse order.
  List<Map<String, dynamic>> get _filteredTrains {
    if (_destFilterCode == null) {
      return _trains;
    }
    if (_destTrainSequence == null) {
      return []; // still loading / failed
    }

    return _trains.where((entry) {
      final number = (entry["train"] ?? {})["number"]?.toString();
      if (number == null) return false;

      final destSeq = _destTrainSequence![number];
      if (destSeq == null) return false; // doesn't reach the filter station

      final hereSeq = (entry["stop"] ?? {})["sequence"] as num?;
      if (hereSeq == null) return true; // no sequence to compare — don't drop it

      return hereSeq < destSeq; // must be travelling here -> filter station
    }).toList();
  }

  @override
  void initState() {
    super.initState();

    final code = widget.initialStationCode;
    if (code == null || code.isEmpty) {
      return;
    }

    _selectedCode = code;
    _selectedName = widget.initialStationName;
    _searchController.text = widget.initialStationName ?? code;
    // Spinner from the very first frame; the fetch itself is deferred so we
    // never call setState() while initState is still running.
    _loading = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _fetch());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _destDebounce?.cancel();
    _searchController.dispose();
    _destFilterController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounce?.cancel();

    if (query.trim().isEmpty) {
      setState(() {
        _suggestions = [];
        _suggestionsVisible = false;
      });
      return;
    }

    _debounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final results = await StationService.searchStations(query.trim());
        if (!mounted) return;
        setState(() {
          _suggestions = results;
          _suggestionsVisible = results.isNotEmpty;
        });
      } catch (_) {
        // Autocomplete failing silently is fine — the field still works.
      }
    });
  }

  void _selectStation(Station station) {
    setState(() {
      _selectedCode = station.code;
      _selectedName = station.name;
      _searchController.text = station.name;
      _suggestions = [];
      _suggestionsVisible = false;
      _destFilterController.clear();
      _destFilterCode = null;
      _destFilterName = null;
      _destTrainSequence = null;
      _destSuggestions = [];
      _destSuggestionsVisible = false;
    });
    FocusScope.of(context).unfocus();
    _fetch();
  }

  void _onDestQueryChanged(String query) {
    _destFilterCode = null; // typing again invalidates the previous pick
    _destTrainSequence = null;
    _destDebounce?.cancel();

    if (query.trim().isEmpty) {
      setState(() {
        _destSuggestions = [];
        _destSuggestionsVisible = false;
      });
      return;
    }

    _destDebounce = Timer(const Duration(milliseconds: 300), () async {
      try {
        final results = await StationService.searchStations(query.trim());
        if (!mounted) return;
        setState(() {
          _destSuggestions = results;
          _destSuggestionsVisible = results.isNotEmpty;
        });
      } catch (_) {
        // Autocomplete failing silently is fine — user can just retype.
      }
    });
  }

  void _selectDestStation(Station station) {
    setState(() {
      _destFilterCode = station.code;
      _destFilterName = station.name;
      _destFilterController.text = station.name;
      _destSuggestions = [];
      _destSuggestionsVisible = false;
    });
    FocusScope.of(context).unfocus();
    _fetchDestBoard();
  }

  void _clearDestFilter() {
    setState(() {
      _destFilterController.clear();
      _destFilterCode = null;
      _destFilterName = null;
      _destTrainSequence = null;
      _destSuggestions = [];
      _destSuggestionsVisible = false;
    });
  }

  /// Pulls the filter station's own live board (also with intermediate
  /// trains) so [_filteredTrains] can keep only the trains common to both
  /// boards — i.e. actually heading through the picked station.
  Future<void> _fetchDestBoard() async {
    final code = _destFilterCode;
    if (code == null) {
      return;
    }

    setState(() {
      _destLoading = true;
      _destTrainSequence = null;
    });

    try {
      final uri = Uri.parse(
        "${AppConfig.baseUrl}/stations/$code/live",
      ).replace(queryParameters: {"hours": "8", "includeIntermediate": "true"});

      final response = await http.get(uri);
      final body = jsonDecode(response.body);

      if (response.statusCode != 200 || body["success"] != true) {
        throw Exception(body["message"] ?? "Failed to load");
      }

      final List raw = body["data"]["data"]["trains"] ?? [];
      final sequenceByNumber = <String, num>{};
      for (final e in raw) {
        final number = (e["train"] ?? {})["number"]?.toString();
        final seq = (e["stop"] ?? {})["sequence"] as num?;
        if (number != null && seq != null) {
          sequenceByNumber[number] = seq;
        }
      }

      if (!mounted || _destFilterCode != code) {
        return; // filter changed mid-flight
      }
      setState(() {
        _destTrainSequence = sequenceByNumber;
        _destLoading = false;
      });
    } catch (_) {
      if (!mounted || _destFilterCode != code) return;
      setState(() {
        _destTrainSequence =
            {}; // couldn't check — show nothing rather than everything
        _destLoading = false;
      });
    }
  }

  Future<void> _fetch() async {
    if (_selectedCode == null) {
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final uri = Uri.parse(
        "${AppConfig.baseUrl}/stations/$_selectedCode/live",
      ).replace(queryParameters: {"hours": "4"});

      final response = await http.get(uri);
      final body = jsonDecode(response.body);

      if (response.statusCode != 200 || body["success"] != true) {
        throw Exception(body["message"] ?? "Failed to load station board");
      }

      final List raw = body["data"]["data"]["trains"] ?? [];

      if (!mounted) return;
      setState(() {
        _trains = raw.cast<Map<String, dynamic>>();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error =
            "Couldn't load the live board for ${_selectedName ?? _selectedCode}";
        _loading = false;
      });
    }
  }

  /// "Xh Ym" once the delay crosses 60 minutes, instead of a raw count
  /// like "113 min".
  String _formatDelay(int minutes) {
    if (minutes < 60) {
      return "$minutes min";
    }
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? "${h}h" : "${h}h ${m}m";
  }

  /// `stop.arrival` / `stop.departure` come back as plain "HH:mm" strings
  /// (not ISO datetimes, unlike the live-train-status endpoint).
  String _fmtHM(String? hm) {
    if (hm == null) {
      return "--";
    }
    try {
      return DateFormat("hh:mm a").format(DateFormat("HH:mm").parse(hm));
    } catch (_) {
      return hm;
    }
  }

  String _fmtIso(String? iso) {
    if (iso == null) {
      return "--";
    }
    try {
      return DateFormat("hh:mm a").format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return "--";
    }
  }

  @override
  Widget build(BuildContext context) {
    final skin = SkinTokens.of(context.watch<ThemeProvider>().skin);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: skin.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: skin.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.podcasts_rounded,
                  color: skin.primaryDeep,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  "Live Station Board",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: skin.text,
                  ),
                ),
              ),
              if (_selectedCode != null)
                IconButton(
                  onPressed: _loading ? null : _fetch,
                  icon: Icon(Icons.refresh, size: 20, color: skin.primary),
                ),
            ],
          ),

          const SizedBox(height: 12),

          TextField(
            controller: _searchController,
            onChanged: _onQueryChanged,
            style: TextStyle(color: skin.text),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: skin.bg,
              hintText: "Search any station (e.g. Bhatapara, BYT)",
              hintStyle: TextStyle(color: skin.dim),
              prefixIcon: Icon(
                Icons.location_on_outlined,
                size: 20,
                color: skin.dim,
              ),
              suffixIcon: _selectedCode == null
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () => setState(() {
                        _searchController.clear();
                        _selectedCode = null;
                        _selectedName = null;
                        _trains = [];
                        _error = null;
                      }),
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),

          if (_suggestionsVisible)
            Container(
              margin: const EdgeInsets.only(top: 6),
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                color: skin.bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: skin.border),
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: _suggestions.length,
                  itemBuilder: (context, i) {
                    final s = _suggestions[i];
                    return ListTile(
                      dense: true,
                      onTap: () => _selectStation(s),
                      leading: Text(
                        s.code,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: skin.primaryDeep,
                        ),
                      ),
                      title: Text(
                        s.name,
                        style: TextStyle(fontSize: 14, color: skin.text),
                      ),
                    );
                  },
                ),
              ),
            ),

          const SizedBox(height: 14),

          if (_selectedCode != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _destFilterController,
                    onChanged: _onDestQueryChanged,
                    style: TextStyle(color: skin.text, fontSize: 13.5),
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: skin.bg,
                      hintText: "Going to (optional) — e.g. Delhi",
                      hintStyle: TextStyle(color: skin.dim, fontSize: 13),
                      prefixIcon: Icon(
                        Icons.filter_alt_outlined,
                        size: 18,
                        color: skin.dim,
                      ),
                      suffixIcon: _destFilterController.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear, size: 16),
                              onPressed: _clearDestFilter,
                            ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  if (_destSuggestionsVisible)
                    Container(
                      margin: const EdgeInsets.only(top: 6),
                      width: double.infinity,
                      constraints: const BoxConstraints(maxHeight: 220),
                      decoration: BoxDecoration(
                        color: skin.bg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: skin.border),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        clipBehavior: Clip.antiAlias,
                        child: ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          itemCount: _destSuggestions.length,
                          itemBuilder: (context, i) {
                            final s = _destSuggestions[i];
                            return ListTile(
                              dense: true,
                              onTap: () => _selectDestStation(s),
                              leading: Text(
                                s.code,
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: skin.primaryDeep,
                                ),
                              ),
                              title: Text(
                                s.name,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: skin.text,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    )
                  else if (_destFilterController.text.trim().isNotEmpty &&
                      _destFilterCode == null)
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 4),
                      child: Text(
                        "Pick a station from the list to filter",
                        style: TextStyle(fontSize: 11.5, color: skin.dim),
                      ),
                    ),
                ],
              ),
            ),

          if (_selectedCode == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                "Search a station above to see live arrivals & departures.",
                style: TextStyle(color: skin.dim, fontSize: 13),
              ),
            )
          else if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                _error!,
                style: TextStyle(color: skin.dim, fontSize: 13),
              ),
            )
          else if (_destLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_filteredTrains.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                _destFilterCode == null
                    ? "No other trains in the next few hours at this station."
                    : "No trains to \"$_destFilterName\" found here right now.",
                style: TextStyle(color: skin.dim, fontSize: 13),
              ),
            )
          else
            ...List.generate(_filteredTrains.length, (i) {
              final entry = _filteredTrains[i];
              final train = entry["train"] ?? {};
              final stop = entry["stop"] ?? {};
              final live = entry["live"] ?? {};

              final String liveType = live["type"]?.toString() ?? "scheduled";
              final int delayMin = (live["delayMinutes"] as num?)?.toInt() ?? 0;
              final bool isDeparted = liveType == "departed";
              final bool isAtStation = liveType == "at-station";
              final String trainNumber = train["number"]?.toString() ?? "";

              final String scheduled = _fmtHM(
                stop["departure"]?.toString() ?? stop["arrival"]?.toString(),
              );

              final String? expectedIso =
                  live["expectedDepartureTime"]?.toString() ??
                  live["expectedArrivalTime"]?.toString() ??
                  live["actualDepartureTime"]?.toString() ??
                  live["actualArrivalTime"]?.toString();

              final String actualOrExpected = expectedIso != null
                  ? _fmtIso(expectedIso)
                  : scheduled;

              return InkWell(
                onTap: trainNumber.isEmpty
                    ? null
                    : () => widget.onTrackTrain?.call(trainNumber),
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  margin: EdgeInsets.only(top: i == 0 ? 0 : 14),
                  padding: const EdgeInsets.only(bottom: 14),
                  decoration: i == _filteredTrains.length - 1
                      ? null
                      : BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: skin.border),
                          ),
                        ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: skin.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              trainNumber,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: skin.primaryDeep,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              train["name"]?.toString() ?? "",
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                color: skin.text,
                              ),
                            ),
                          ),
                          if (scheduled != actualOrExpected)
                            Text(
                              scheduled,
                              style: TextStyle(
                                fontSize: 12,
                                color: skin.dim,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                          const SizedBox(width: 6),
                          Text(
                            actualOrExpected,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: delayMin > 0
                                  ? Colors.red.shade400
                                  : skin.text,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.chevron_right, size: 18, color: skin.dim),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "${train["source"] ?? ""}  →  ${train["destination"] ?? ""}"
                        "${live["platform"] != null ? " · Platform ${live["platform"]}" : ""}",
                        style: TextStyle(fontSize: 12, color: skin.dim),
                      ),
                      if (isDeparted || isAtStation || delayMin > 0) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: delayMin > 0
                                ? Colors.red.shade50
                                : Colors.green.shade50,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            isDeparted
                                ? "Left ${_selectedName ?? _selectedCode} at $actualOrExpected"
                                      "${delayMin > 0 ? " · ${_formatDelay(delayMin)} late" : ""}"
                                : isAtStation
                                ? "At the station now"
                                      "${delayMin > 0 ? " · ${_formatDelay(delayMin)} late" : ""}"
                                : "Delayed by ${_formatDelay(delayMin)}",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: delayMin > 0
                                  ? Colors.red.shade700
                                  : Colors.green.shade700,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}
