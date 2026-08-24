import 'dart:convert';
import 'package:http/http.dart' as http;

import '../core/config/app_config.dart';
import '../models/station.dart';

class StationService {
  static Future<List<Station>> searchStations(String query) async {
    if (query.trim().isEmpty) return [];

    final uri = Uri.parse("${AppConfig.baseUrl}/stations/search").replace(
      queryParameters: {"q": query},
    );

    final response = await http.get(uri).timeout(
      AppConfig.apiTimeout,
      onTimeout: () => throw Exception(
        "Request timed out — the server may be waking up. Please try again.",
      ),
    );

    if (response.statusCode == 200) {
      final Map<String, dynamic> body = json.decode(response.body);
      final List data = body["data"] ?? [];

      return data
          .map<Station>((e) => Station.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    throw Exception("Failed to load stations (status ${response.statusCode})");
  }
}
