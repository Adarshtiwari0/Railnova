import '../core/utils/format.dart';

/// Maps to RailRadar's "Trains Between Stations" response shape
/// (GET /v1/trains/between/{from}/{to} — see https://railradar.in/docs/trains-between-stations).
///
/// Each entry in `data.trains[]` looks like:
/// {
///   "train": { "number", "name", "type", "runDays": [...] },
///   "from": { "departure": "06:00", "day": 1, "sequence": 1 },
///   "to": { "arrival": "07:55", "day": 1, "sequence": 11 },
///   "distance": 62.2,
///   "duration": 115,              // minutes
///   "totalHaltsBetween": 6,
///   "live": {                     // only present when live=true was requested
///     "type": "upcoming" | "running" | "departed" | ...,
///     "expectedArrivalTime": "...",
///     "platform": "2",
///     "delayMinutes": 0
///   }
/// }

class Train {
  final String trainNumber;
  final String trainName;
  final String type;
  final List<String> runDays;

  /// Station codes for the searched route (from the top-level response, not
  /// per-train — RailRadar only puts the code once at `data.from.code`).
  final String from;
  final String to;

  final String? departureTime; // "HH:mm", from-station departure
  final String? arrivalTime; // "HH:mm", to-station arrival
  final int? departureDay; // 1 = day of departure, 2 = next day, etc.
  final int? arrivalDay;

  final double? distanceKm;
  final int? durationMinutes;
  final int? totalHaltsBetween;

  // Only populated when the search was made with live=true.
  final String? liveStatus;
  final String? liveDelayMinutes;
  final String? livePlatform;

  /// ISO datetime for when the train left/will leave/is expected at the
  /// `from` station — RailRadar uses different key names depending on
  /// `liveStatus` ("upcoming" -> expected*, "departed" -> actual*), so this
  /// tries all of them in priority order.
  final String? liveEventTime;

  Train({
    required this.trainNumber,
    required this.trainName,
    required this.type,
    required this.runDays,
    required this.from,
    required this.to,
    this.departureTime,
    this.arrivalTime,
    this.departureDay,
    this.arrivalDay,
    this.distanceKm,
    this.durationMinutes,
    this.totalHaltsBetween,
    this.liveStatus,
    this.liveDelayMinutes,
    this.livePlatform,
    this.liveEventTime,
  });

  factory Train.fromJson(
    Map<String, dynamic> json, {
    required String fromCode,
    required String toCode,
  }) {
    final train = json["train"] ?? {};
    final fromInfo = json["from"] ?? {};
    final toInfo = json["to"] ?? {};
    final live = json["live"];

    return Train(
      trainNumber: train["number"]?.toString() ?? "",
      trainName: train["name"]?.toString() ?? "",
      type: train["type"]?.toString() ?? "",
      runDays:
          (train["runDays"] as List?)?.map((e) => e.toString()).toList() ?? [],
      from: fromCode,
      to: toCode,
      departureTime: fromInfo["departure"]?.toString(),
      arrivalTime: toInfo["arrival"]?.toString(),
      departureDay: fromInfo["day"] is int ? fromInfo["day"] : null,
      arrivalDay: toInfo["day"] is int ? toInfo["day"] : null,
      distanceKm: (json["distance"] as num?)?.toDouble(),
      durationMinutes: json["duration"] is int ? json["duration"] : null,
      totalHaltsBetween: json["totalHaltsBetween"] is int
          ? json["totalHaltsBetween"]
          : null,
      liveStatus: live?["type"]?.toString(),
      liveDelayMinutes: live?["delayMinutes"]?.toString(),
      livePlatform: live?["platform"]?.toString(),
      liveEventTime:
          live?["expectedDepartureTime"]?.toString() ??
          live?["expectedArrivalTime"]?.toString() ??
          live?["actualDepartureTime"]?.toString() ??
          live?["actualArrivalTime"]?.toString(),
    );
  }

  /// "2h 15m" style formatting for [durationMinutes].
  String get formattedDuration {
    if (durationMinutes == null) return "--";
    final h = durationMinutes! ~/ 60;
    final m = durationMinutes! % 60;
    if (h == 0) return "${m}m";
    if (m == 0) return "${h}h";
    return "${h}h ${m}m";
  }

  bool get isDelayed {
    final d = int.tryParse(liveDelayMinutes ?? "");
    return d != null && d > 0;
  }

  /// True once RailRadar has actually told us a delay figure for this
  /// train (even 0) — false means "no live data", which the UI must show
  /// as a neutral/unknown state rather than silently assuming on-time.
  bool get hasLiveDelayData => int.tryParse(liveDelayMinutes ?? "") != null;

  /// RailRadar can send a negative delay for a train running ahead of
  /// schedule.
  bool get isEarly {
    final d = int.tryParse(liveDelayMinutes ?? "");
    return d != null && d < 0;
  }

  bool get isOnTime => hasLiveDelayData && !isDelayed && !isEarly;

  /// "Xh Ym" for however early the train is running, mirroring
  /// [formattedLiveDelay] but for negative delay values.
  String get formattedEarlyBy {
    final minutes = (int.tryParse(liveDelayMinutes ?? "") ?? 0).abs();
    if (minutes < 60) return "${minutes}m";
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? "${h}h" : "${h}h ${m}m";
  }

  bool get hasDepartedFromStation => liveStatus == "departed";

  /// RailRadar only sets `live.type = "departed"` once it has an actual
  /// GPS/crowdsourced confirmation for THIS train — a lot of trains don't
  /// have that yet, so `hasDepartedFromStation` alone stays false even long
  /// after the scheduled departure time has passed. This falls back to
  /// comparing the scheduled departure (for [journeyDate]) against "now" so
  /// the app can still show a "departed" badge instead of silently hiding
  /// it. Prefer the live-confirmed value when it's available — it's more
  /// accurate (accounts for real delays).
  bool hasLikelyDeparted(DateTime journeyDate) {
    if (hasDepartedFromStation) return true;

    final scheduled = scheduledDepartureDateTime(journeyDate);
    if (scheduled == null) return false;

    return DateTime.now().isAfter(scheduled);
  }

  /// The scheduled departure as a real [DateTime], combining [departureTime]
  /// ("HH:mm") with [departureDay] (1 = day of journey, 2 = next day, etc.)
  /// against the journey's calendar date. Returns null if the time couldn't
  /// be parsed.
  DateTime? scheduledDepartureDateTime(DateTime journeyDate) {
    final time = departureTime;
    if (time == null) return null;

    final parts = time.split(":");
    if (parts.length != 2) return null;

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;

    final dayOffset = (departureDay ?? 1) - 1;

    return DateTime(
      journeyDate.year,
      journeyDate.month,
      journeyDate.day,
    ).add(Duration(days: dayOffset, hours: hour, minutes: minute));
  }

  /// "Xh Ym" once the delay crosses 60 minutes, instead of a raw count
  /// like "113m".
  String get formattedLiveDelay {
    final minutes = int.tryParse(liveDelayMinutes ?? "") ?? 0;
    return formatDelay(minutes);
  }
}
