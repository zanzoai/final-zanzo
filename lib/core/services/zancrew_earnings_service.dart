// lib/core/services/zancrew_earnings_service.dart

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:zanzo_frontend/core/services/api_service.dart';

class ZanCrewEarningsService {
  /// Base endpoint
  static String get _base => "${ApiService.baseUrl}/earnings";

  /// Fetch earnings (always fresh — never cached)
  static Future<Map<String, dynamic>> getEarnings(String crewUserId) async {
    // Add timestamp to avoid HTTP caching at all layers
    final uri = Uri.parse(
      "$_base/$crewUserId?ts=${DateTime.now().millisecondsSinceEpoch}",
    );

    final response = await http.get(
      uri,
      headers: {
        "Cache-Control": "no-cache, no-store, must-revalidate",
        "Pragma": "no-cache",
        "Expires": "0",
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        "Failed to load earnings: ${response.statusCode} ${response.body}",
      );
    }

    try {
      final decoded = jsonDecode(response.body);
      return Map<String, dynamic>.from(decoded);
    } catch (e) {
      throw Exception("Invalid JSON format: $e");
    }
  }
}
