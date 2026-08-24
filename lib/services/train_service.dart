import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/config/app_config.dart';
import '../models/train_model.dart';

class TrainService {
  String _errorFrom(http.Response response, String fallback) {
    try {
      final body = jsonDecode(response.body);
      return body["message"] ?? fallback;
    } catch (_) {
      return "$fallback (status ${response.statusCode})";
    }
  }

  /// [from] and [to] MUST be station codes (e.g. "NDLS", "BPL"), not full
  /// station names — the RailRadar API returns 400 Bad Request otherwise.
  ///
  /// Set [live] to true to have each train enriched with a live delay /
  /// platform snapshot at the `from` station (costs one extra bit of work
  /// upstream, so it's opt-in rather than always-on).
  Future<List<Train>> searchTrains(
    String from,
    String to,
    String? date, {
    bool live = false,
  }) async {
    final uri = Uri.parse("${AppConfig.baseUrl}/trains/search").replace(
      queryParameters: {
        "from": from,
        "to": to,
        if (date != null && date.isNotEmpty) "date": date,
        if (live) "live": "true",
      },
    );

    final response = await http.get(uri).timeout(
      AppConfig.apiTimeout,
      onTimeout: () => throw Exception(
        "Request timed out — the server may be waking up. Please try again.",
      ),
    );

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final railRadarData = body["data"]?["data"];
      if (railRadarData == null) {
        throw Exception(_errorFrom(response, "Unexpected response from server"));
      }

      final String fromCode = railRadarData["from"]?["code"]?.toString() ?? from;
      final String toCode = railRadarData["to"]?["code"]?.toString() ?? to;

      final List trains = railRadarData["trains"] ?? [];

      return trains
          .map(
            (e) => Train.fromJson(
              e as Map<String, dynamic>,
              fromCode: fromCode,
              toCode: toCode,
            ),
          )
          .toList();
    }

    throw Exception(_errorFrom(response, "Failed to load trains"));
  }

  /// Raw live-status payload for a train number — see
  /// https://railradar.in/docs/live-train-status for the full shape
  /// (status, delayMinutes, currentLocation, previousHalt, nextHalt, route[]).
  /// [date] (YYYY-MM-DD) picks which journey to show — omit for "today"
  /// (RailRadar auto-detects the most recent journey), or pass e.g.
  /// yesterday's date to see that journey's status.
  Future<Map<String, dynamic>> getLiveStatus(String trainNumber, {String? date}) async {
    final uri = Uri.parse("${AppConfig.baseUrl}/trains/live/$trainNumber").replace(
      queryParameters: date != null ? {"date": date} : null,
    );
    final response = await http.get(uri).timeout(
      AppConfig.apiTimeout,
      onTimeout: () => throw Exception(
        "Request timed out — the server may be waking up. Please try again.",
      ),
    );

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final data = body["data"]?["data"];
      if (data is! Map<String, dynamic>) {
        throw Exception(_errorFrom(response, "Unexpected response from server"));
      }
      return data;
    }

    throw Exception(_errorFrom(response, "Failed to load live status"));
  }

  /// Raw train-details payload for a train number — see
  /// https://railradar.in/docs/get-train-details for the full shape
  /// (train info + full route/stops).
  Future<Map<String, dynamic>> getTrainDetails(String trainNumber) async {
    final uri = Uri.parse("${AppConfig.baseUrl}/trains/details/$trainNumber");
    final response = await http.get(uri).timeout(
      AppConfig.apiTimeout,
      onTimeout: () => throw Exception(
        "Request timed out — the server may be waking up. Please try again.",
      ),
    );

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final data = body["data"]?["data"];
      if (data is! Map<String, dynamic>) {
        throw Exception(_errorFrom(response, "Unexpected response from server"));
      }
      return data;
    }

    throw Exception(_errorFrom(response, "Failed to load train details"));
  }

  /// Fast local search by train number OR name (e.g. "sar" -> Sarnath
  /// Express, Saraighat Express...). Backed by our own `trains` table, not
  /// a live RailRadar call, so it's safe to call on every keystroke.
  Future<List<Map<String, dynamic>>> lookupTrains(String query) async {
    if (query.trim().isEmpty) return [];

    final uri = Uri.parse(
      "${AppConfig.baseUrl}/trains/lookup",
    ).replace(queryParameters: {"q": query});

    final response = await http.get(uri).timeout(
      AppConfig.apiTimeout,
      onTimeout: () => throw Exception(
        "Request timed out — the server may be waking up. Please try again.",
      ),
    );

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final List results = body["data"] ?? [];
      return results.cast<Map<String, dynamic>>();
    }

    throw Exception(_errorFrom(response, "Failed to search trains"));
  }

  /// Live arrival/departure board for a station — see
  /// https://railradar.in/docs/station-live-board for the full shape
  /// (station, window, trains[] each with train/stop/live).
  Future<Map<String, dynamic>> getStationLiveBoard(
    String stationCode, {
    int hours = 4,
  }) async {
    final uri = Uri.parse(
      "${AppConfig.baseUrl}/stations/$stationCode/live",
    ).replace(queryParameters: {"hours": "$hours"});

    final response = await http.get(uri).timeout(
      AppConfig.apiTimeout,
      onTimeout: () => throw Exception(
        "Request timed out — the server may be waking up. Please try again.",
      ),
    );

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body);
      final data = body["data"]?["data"];
      if (data is! Map<String, dynamic>) {
        throw Exception(_errorFrom(response, "Unexpected response from server"));
      }
      return data;
    }

    throw Exception(_errorFrom(response, "Failed to load station board"));
  }
}
