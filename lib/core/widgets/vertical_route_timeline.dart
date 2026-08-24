import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/skin_tokens.dart';
import '../utils/format.dart';

/// A top-to-bottom, fully expanded journey timeline.
///
/// - Halting stations render in full: name, platform, and time.
/// - Pass-through (non-halting) stations are collapsed into a single thin
///   line behind the halt station before them — tap anywhere on that halt
///   station's row to reveal them, tap again to collapse (same idea as
///   Where Is My Train).
/// - Stations already crossed show "scheduled-actual" with the actual part
///   in red when late (e.g. "12:00-12:10"), or just the time in black when
///   on time.
/// - A pulsing train marker sits at the current position; the rail line
///   above it fills green (crossed), grey below (not yet reached). Tapping
///   the marker — or bumping [popupTrigger] after a refresh — briefly shows
///   a floating card with the delay and remaining distance to the next
///   station, which fades away on its own after a few seconds.
class VerticalRouteTimeline extends StatefulWidget {
  final List<Map<String, dynamic>> route;
  final Map<String, dynamic>? currentLocation;
  final int? delayMinutes;
  final SkinTokens skin;
  final bool notStarted;
  final String? startsInLabel;
  final Map<String, dynamic>? previousHalt;
  final Map<String, dynamic>? nextHalt;

  /// Bump this (e.g. a counter incremented on every successful fetch) to
  /// re-trigger the floating popup after a refresh.
  final int popupTrigger;

  const VerticalRouteTimeline({
    super.key,
    required this.route,
    required this.currentLocation,
    required this.skin,
    this.delayMinutes,
    this.notStarted = false,
    this.startsInLabel,
    this.previousHalt,
    this.nextHalt,
    this.popupTrigger = 0,
  });

  @override
  State<VerticalRouteTimeline> createState() => _VerticalRouteTimelineState();
}

class _VerticalRouteTimelineState extends State<VerticalRouteTimeline>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  final Map<int, GlobalKey> _rowKeys = {};

  // Keyed by the *halt* station's index in widget.route. A group's
  // pass-through children are shown only when its halt index is in here.
  final Set<int> _expandedHalts = {};
  bool _autoExpandedCurrent = false;

  bool _showPopup = false;
  int _lastPopupTrigger = 0;
  Timer? _popupHideTimer;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1300),
    )..repeat(reverse: true);

    _lastPopupTrigger = widget.popupTrigger;
    if (widget.currentLocation != null) {
      _ensureCurrentExpanded();
      _flashPopup();
    }
  }

  @override
  void didUpdateWidget(covariant VerticalRouteTimeline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.popupTrigger != _lastPopupTrigger) {
      _lastPopupTrigger = widget.popupTrigger;
      _ensureCurrentExpanded();
      _flashPopup();
    }
  }

  /// Makes sure the group holding the current position is expanded, so the
  /// pulsing marker (and the popup right under it) is actually visible
  /// after a refresh — even if the train has moved into a different,
  /// still-collapsed group, or the user had collapsed it earlier.
  void _ensureCurrentExpanded() {
    final loc = widget.currentLocation;
    if (loc == null) return;
    final currentIdx = _indexForSequence(loc["sequence"]);
    if (currentIdx == -1) return;

    for (final g in _buildGroups()) {
      if (g.contains(currentIdx)) {
        _expandedHalts.add(g.first);
        break;
      }
    }
  }

  void _flashPopup() {
    _popupHideTimer?.cancel();
    setState(() => _showPopup = true);
    _popupHideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _showPopup = false);
    });
  }

  void _togglePopup() {
    if (_showPopup) {
      _popupHideTimer?.cancel();
      setState(() => _showPopup = false);
    } else {
      _flashPopup();
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _popupHideTimer?.cancel();
    super.dispose();
  }

  int _indexForSequence(dynamic seq) {
    return widget.route.indexWhere((s) => s["sequence"] == seq);
  }

  /// Groups the route into [haltIndex, ...passThroughIndices] chunks. The
  /// very first station is always treated as a group head even if, for
  /// some reason, `isHalt` wasn't true for it.
  List<List<int>> _buildGroups() {
    final groups = <List<int>>[];

    for (int i = 0; i < widget.route.length; i++) {
      final isHalt = widget.route[i]["isHalt"] == true;

      if (isHalt || groups.isEmpty) {
        groups.add([i]);
      } else {
        groups.last.add(i);
      }
    }

    return groups;
  }

  void _scrollToCurrent() {
    final loc = widget.currentLocation;
    if (loc == null) return;

    final idx = _indexForSequence(loc["sequence"]);
    final key = _rowKeys[idx];
    if (key?.currentContext == null) return;

    Scrollable.ensureVisible(
      key!.currentContext!,
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
      alignment: 0.3,
    );
  }

  String _fmtTime(String? iso) {
    if (iso == null) return "--";
    try {
      return DateFormat("hh:mm a").format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return "--";
    }
  }

  /// "[current station] · ~X km to [next station]" line for the popup.
  ///
  /// Previously this estimated the remaining distance from `segmentProgress`
  /// between the previous and next *halt* only, on the assumption that
  /// RailRadar puts `distance` solely on those two objects. That assumption
  /// was wrong — every item in `route` (including pass-through, non-halt
  /// stations) carries its own `distance`. Interpolating from the previous
  /// halt badly overshoots whenever the train is currently sitting at a
  /// non-halt station much closer to the next halt than the previous halt
  /// is — which is exactly what produced "~3 km to Raipur Jn." while the
  /// train was actually still ~24 km out, sitting at Siliari. Reading the
  /// current station's own `distance` straight off `route` is both simpler
  /// and exact.
  ({String? currentName, String? label}) _positionInfo() {
    final loc = widget.currentLocation;
    if (loc == null) return (currentName: null, label: null);

    final idx = _indexForSequence(loc["sequence"]);
    final current = (idx >= 0 && idx < widget.route.length)
        ? widget.route[idx]
        : null;
    final currentName =
        current?["stationName"]?.toString() ??
        current?["stationCode"]?.toString();
    final currentDist = (current?["distance"] as num?)?.toDouble();

    final nextDist = (widget.nextHalt?["distance"] as num?)?.toDouble();
    final nextName =
        widget.nextHalt?["stationName"]?.toString() ??
        widget.nextHalt?["stationCode"]?.toString();

    if (currentDist == null || nextDist == null || nextName == null) {
      return (currentName: currentName, label: null);
    }

    final remaining = nextDist - currentDist;
    if (remaining < 0) return (currentName: currentName, label: null);

    return (
      currentName: currentName,
      label: "~${remaining.round()} km to $nextName",
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.route.isEmpty) return const SizedBox.shrink();

    final currentIdx = widget.currentLocation != null
        ? _indexForSequence(widget.currentLocation!["sequence"])
        : -1;

    // "Moving" = the API gave us a mid-segment progress value (not sitting
    // right at 0%, i.e. freshly at a halt) — used to bob the marker a bit.
    final progress = (widget.currentLocation?["segmentProgress"] as num?)
        ?.toDouble();
    final moving = progress != null && progress > 0.03;

    final groups = _buildGroups();

    // The group containing the current position starts expanded, so the
    // train's neighbourhood is visible without the user having to tap
    // anything first — everything else stays collapsed until tapped.
    if (!_autoExpandedCurrent && currentIdx != -1) {
      for (final g in groups) {
        if (g.contains(currentIdx)) {
          _expandedHalts.add(g.first);
          break;
        }
      }
      _autoExpandedCurrent = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
    }

    final rows = <Widget>[];

    for (final group in groups) {
      final haltIdx = group.first;
      final passThroughs = group.skip(1).toList();
      final isLastGroup = group == groups.last;
      final expanded = _expandedHalts.contains(haltIdx);
      final groupHasCurrent = group.contains(currentIdx);

      // The whole row is tappable when it hides pass-through stations —
      // no need to hit a tiny arrow icon. Tapping the current-position
      // group also re-shows the floating popup.
      rows.add(
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (groupHasCurrent) _togglePopup();
            if (passThroughs.isEmpty) return;
            setState(() {
              if (expanded) {
                _expandedHalts.remove(haltIdx);
              } else {
                _expandedHalts.add(haltIdx);
              }
            });
          },
          child: _StationRow(
            skin: widget.skin,
            key: _rowKeys[haltIdx] ??= GlobalKey(),
            station: widget.route[haltIdx],
            isCurrent: haltIdx == currentIdx,
            crossed: currentIdx != -1 && haltIdx < currentIdx,
            upcoming: currentIdx != -1 && haltIdx > currentIdx,
            isLastOverall: isLastGroup && passThroughs.isEmpty,
            hasLineBelow: !isLastGroup || passThroughs.isNotEmpty,
            isOrigin: haltIdx == 0,
            isDestination: isLastGroup && passThroughs.isEmpty,
            moving: moving,
            pulseController: _pulseController,
            fmtTime: _fmtTime,
            trailing: passThroughs.isEmpty
                ? null
                : Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: widget.skin.dim,
                  ),
          ),
        ),
      );

      // Popup sits right under whichever row is actually the current
      // position — the halt row above if the train is sitting at a halt,
      // or (below, once we hit it) the matching pass-through row if the
      // train is running between two halts, which is most of the time.
      if (haltIdx == currentIdx) {
        final pos = _positionInfo();
        rows.add(
          _PositionPopup(
            visible: _showPopup,
            delayMinutes: widget.delayMinutes,
            currentStationName: pos.currentName,
            distanceLabel: pos.label,
            notStarted: widget.notStarted,
            startsInLabel: widget.startsInLabel,
          ),
        );
      }

      if (expanded) {
        for (int p = 0; p < passThroughs.length; p++) {
          final idx = passThroughs[p];
          final isLastInGroup = p == passThroughs.length - 1;

          rows.add(
            _StationRow(
              key: _rowKeys[idx] ??= GlobalKey(),
              skin: widget.skin,
              station: widget.route[idx],
              isCurrent: idx == currentIdx,
              crossed: currentIdx != -1 && idx < currentIdx,
              upcoming: currentIdx != -1 && idx > currentIdx,
              isLastOverall: isLastGroup && isLastInGroup,
              hasLineBelow: !(isLastGroup && isLastInGroup),
              isDestination: isLastGroup && isLastInGroup,
              moving: moving,
              pulseController: _pulseController,
              fmtTime: _fmtTime,
              compact: true,
            ),
          );

          if (idx == currentIdx) {
            final pos = _positionInfo();
            rows.add(
              _PositionPopup(
                visible: _showPopup,
                delayMinutes: widget.delayMinutes,
                currentStationName: pos.currentName,
                distanceLabel: pos.label,
                notStarted: widget.notStarted,
                startsInLabel: widget.startsInLabel,
              ),
            );
          }
        }
      }
    }

    return Column(children: rows);
  }
}

/// Floating card that briefly shows delay + remaining distance near the
/// train's current position, then fades itself out.
class _PositionPopup extends StatelessWidget {
  final bool visible;
  final int? delayMinutes;
  final String? currentStationName;
  final String? distanceLabel;
  final bool notStarted;
  final String? startsInLabel;

  const _PositionPopup({
    required this.visible,
    required this.delayMinutes,
    required this.distanceLabel,
    this.currentStationName,
    this.notStarted = false,
    this.startsInLabel,
  });

  /// Formats a delay in minutes as "Xh Ym" once it crosses 60 minutes,
  /// instead of showing a raw minute count like "168 min".
  static String _formatDelay(int minutes) => formatDelay(minutes);

  @override
  Widget build(BuildContext context) {
    final bool late = (delayMinutes ?? 0) > 0;

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: !visible
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(left: 46, top: 4, bottom: 10),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 200),
                opacity: visible ? 1 : 0,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!notStarted && currentStationName != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            "At $currentStationName",
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                      if (!notStarted && distanceLabel != null)
                        Text(
                          distanceLabel!,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: notStarted
                              ? Colors.blueGrey.shade50
                              : (late
                                    ? Colors.red.shade50
                                    : Colors.green.shade50),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          notStarted
                              ? (startsInLabel ?? "Train not started yet")
                              : (late
                                    ? "Delayed by ${_formatDelay(delayMinutes ?? 0)}"
                                    : "Running on time"),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: notStarted
                                ? Colors.blueGrey.shade700
                                : (late
                                      ? Colors.red.shade700
                                      : Colors.green.shade700),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Updated a few seconds ago",
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _StationRow extends StatelessWidget {
  final Map<String, dynamic> station;
  final bool isCurrent;
  final bool crossed;
  final bool upcoming;
  final bool isLastOverall;
  final bool hasLineBelow;
  final bool isOrigin;
  final bool isDestination;
  final bool moving;
  final SkinTokens skin;
  final AnimationController pulseController;
  final String Function(String?) fmtTime;
  final bool compact;
  final Widget? trailing;

  const _StationRow({
    super.key,
    required this.station,
    required this.isCurrent,
    required this.crossed,
    required this.upcoming,
    required this.isLastOverall,
    required this.hasLineBelow,
    required this.skin,
    required this.pulseController,
    required this.fmtTime,
    this.isOrigin = false,
    this.isDestination = false,
    this.moving = false,
    this.compact = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final bool isHalt = station["isHalt"] == true;
    final String name =
        station["stationName"]?.toString() ??
        station["stationCode"]?.toString() ??
        "";
    final String code = station["stationCode"]?.toString() ?? "";
    final String? platform = station["platform"]?.toString();
    final num? distanceKm = station["distance"] as num?;

    final String? scheduled =
        station["scheduledArrival"] ?? station["scheduledDeparture"];
    final String? actual =
        station["actualDeparture"] ?? station["actualArrival"];
    final int? delay =
        (station["delayDeparture"] ?? station["delayArrival"]) as int?;

    return Padding(
      padding: EdgeInsets.only(bottom: isLastOverall ? 0 : (compact ? 6 : 2)),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Rail column: dot + line down to the next station.
            SizedBox(
              width: 34,
              child: Column(
                children: [
                  isCurrent
                      ? AnimatedBuilder(
                          animation: pulseController,
                          builder: (context, _) {
                            final glow = 4 + pulseController.value * 5;
                            final bob = moving
                                ? (pulseController.value - 0.5) * 6
                                : 0.0;
                            return Transform.translate(
                              offset: Offset(0, bob),
                              child: Container(
                                width: 22,
                                height: 22,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xff43A047),
                                      Color(0xff66BB6A),
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.green.withValues(alpha: .5),
                                      blurRadius: glow,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.train_rounded,
                                  color: Colors.white,
                                  size: 13,
                                ),
                              ),
                            );
                          },
                        )
                      : Container(
                          width: isHalt ? 13 : 7,
                          height: isHalt ? 13 : 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: crossed
                                ? Colors.blue.shade500
                                : Colors.grey.shade300,
                            border: isHalt
                                ? Border.all(color: Colors.white, width: 2)
                                : null,
                          ),
                        ),
                  if (hasLineBelow)
                    Expanded(
                      child: Container(
                        width: 3,
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        color: crossed || isCurrent
                            ? Colors.green.shade400
                            : Colors.grey.shade300,
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(width: 12),

            // Station info.
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: isLastOverall ? 0 : (compact ? 8 : 16),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  name,
                                  style: TextStyle(
                                    fontSize: compact ? 12 : 15,
                                    fontWeight: compact
                                        ? FontWeight.w500
                                        : FontWeight.bold,
                                    color: upcoming
                                        ? skin.dim
                                        : (compact ? skin.dim : skin.text),
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isOrigin || isDestination) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isDestination
                                        ? Colors.red.shade50
                                        : Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    isDestination ? "END" : "START",
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: isDestination
                                          ? Colors.red.shade600
                                          : Colors.blue.shade600,
                                    ),
                                  ),
                                ),
                              ],
                              if (trailing != null) ...[
                                const SizedBox(width: 4),
                                trailing!,
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Text(
                                code,
                                style: TextStyle(fontSize: 11, color: skin.dim),
                              ),
                              if (distanceKm != null) ...[
                                const SizedBox(width: 6),
                                Text(
                                  "${distanceKm.round()} km",
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: skin.dim,
                                  ),
                                ),
                              ],
                              if (isHalt && platform != null) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 5,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.indigo.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    "PF $platform",
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.indigo.shade600,
                                    ),
                                  ),
                                ),
                              ],
                              if (!isHalt) ...[
                                const SizedBox(width: 6),
                                Text(
                                  "does not halt",
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontStyle: FontStyle.italic,
                                    color: skin.dim,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Halt stations get full Arrival + Departure detail
                    // (scheduled time, and the real one in red if late);
                    // pass-through rows keep a single compact time.
                    compact
                        ? _TimeLabel(
                            scheduled: scheduled,
                            actual: actual,
                            delay: delay,
                            crossedOrCurrent: crossed || isCurrent,
                            upcoming: upcoming,
                            fmtTime: fmtTime,
                            skin: skin,
                          )
                        : _ArrDepTimes(
                            station: station,
                            fmtTime: fmtTime,
                            skin: skin,
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

/// Shows Arrival and Departure as two stacked rows, each with the
/// scheduled time and — once known — the real time in red if it's late
/// (e.g. "8:36 PM  8:57 PM"). Rows for an event that doesn't apply (no
/// arrival at the origin, no departure at the destination) are skipped.
class _ArrDepTimes extends StatelessWidget {
  final Map<String, dynamic> station;
  final String Function(String?) fmtTime;
  final SkinTokens skin;

  const _ArrDepTimes({
    required this.station,
    required this.fmtTime,
    required this.skin,
  });

  Widget _row(String label, String? scheduled, String? actual, int? delay) {
    if (scheduled == null && actual == null) return const SizedBox.shrink();

    final bool late = (delay ?? 0) > 0;
    final bool known = actual != null;

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: skin.dim)),
          const SizedBox(width: 5),
          Text(
            fmtTime(scheduled),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: known ? skin.text : skin.dim,
            ),
          ),
          if (known && late) ...[
            const SizedBox(width: 4),
            Text(
              fmtTime(actual),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.red.shade600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _row(
          "Arr",
          station["scheduledArrival"],
          station["actualArrival"],
          station["delayArrival"] as int?,
        ),
        _row(
          "Dep",
          station["scheduledDeparture"],
          station["actualDeparture"],
          station["delayDeparture"] as int?,
        ),
      ],
    );
  }
}

class _TimeLabel extends StatelessWidget {
  final String? scheduled;
  final String? actual;
  final int? delay;
  final bool crossedOrCurrent;
  final bool upcoming;
  final String Function(String?) fmtTime;
  final SkinTokens skin;

  const _TimeLabel({
    required this.scheduled,
    required this.actual,
    required this.delay,
    required this.crossedOrCurrent,
    required this.upcoming,
    required this.fmtTime,
    required this.skin,
  });

  /// RailRadar doesn't always populate the actual timestamp field even when
  /// it does give a delay (in minutes) for that station — without this,
  /// the timeline would silently show the on-time scheduled time for a
  /// station the train left late. Derived only when [delay] is known.
  String? _estimatedActual() {
    if (scheduled == null || delay == null || delay! <= 0) return null;
    try {
      return DateTime.parse(
        scheduled!,
      ).add(Duration(minutes: delay!)).toIso8601String();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveActual = actual ?? _estimatedActual();

    if (crossedOrCurrent && effectiveActual != null) {
      final bool late = (delay ?? 0) > 0;

      if (!late) {
        return Text(
          fmtTime(effectiveActual),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: skin.text,
          ),
        );
      }

      // "12:00-12:10" — scheduled time in the theme's text color, actual/late time in red.
      return RichText(
        text: TextSpan(
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: skin.text,
          ),
          children: [
            TextSpan(text: fmtTime(scheduled)),
            TextSpan(
              text: "-",
              style: TextStyle(color: skin.dim),
            ),
            TextSpan(
              text: fmtTime(effectiveActual),
              style: TextStyle(color: Colors.red.shade600),
            ),
          ],
        ),
      );
    }

    if (upcoming || crossedOrCurrent) {
      return Text(
        fmtTime(scheduled),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: skin.dim,
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
