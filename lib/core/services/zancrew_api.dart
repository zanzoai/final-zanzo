// This file handles ZenCrew profile creation, onboarding status, online/offline toggle, dev verification, and rating retrieval.

// lib/core/services/zancrew_api.dart

import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:zanzo_frontend/core/services/api_service.dart';

class ZanCrewApi {
  static Uri _u(String path) => Uri.parse("${ApiService.baseUrl}$path");

  static Future<http.Response> _call(
    Future<http.Response> Function(Map<String, String> h) fn,
  ) => ApiService.callWithRefresh(fn);

  // ---------------------------------------------------------------------------
  // 1) UPSERT PROFILE (buckets + radius + status)
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>> upsertProfile({
    required String userId,
    required List<String> buckets,
    required int radiusKm,
    String? status, // pending | active | rejected
  }) async {
    final body = {
      "user_id": userId,
      "buckets": buckets,
      "radius_km": radiusKm,
      "status": status ?? "pending",
    };

    final res = await _call(
      (h) => http.post(_u("/zancrew/profile"), headers: h, body: jsonEncode(body)),
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception("Failed to save ZanCrew profile: ${res.body}");
    }

    final decoded = jsonDecode(res.body);

    if (decoded is Map<String, dynamic>) {
      if (decoded['profile'] is Map<String, dynamic>) {
        return Map<String, dynamic>.from(decoded['profile']);
      }
      return decoded;
    }

    throw Exception("Unexpected response: ${res.body}");
  }

  // ---------------------------------------------------------------------------
  // 2) GET PROFILE (returns null if not created)
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>?> getProfile(String userId) async {
    final res = await _call((h) => http.get(_u("/zancrew/profile/$userId"), headers: h));

    if (res.statusCode == 404) return null;

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception("Failed to load profile: ${res.body}");
    }

    final decoded = jsonDecode(res.body);

    if (decoded is Map<String, dynamic>) {
      if (decoded['status'] == "off") return null;

      if (decoded["profile"] is Map<String, dynamic>) {
        return Map<String, dynamic>.from(decoded["profile"]);
      }

      return decoded;
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // 3) GET STATE (onboarding state machine)
  //     /zancrew/state?user_id=xxx
  // Returns:
  //   {
  //     "state": "no_profile" | "incomplete" | "verified",
  //     "profile": { ... } or null
  //   }
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>?> getState(String userId) async {
    final res = await _call((h) => http.get(_u("/zancrew/state?user_id=$userId"), headers: h));

    if (res.statusCode == 404) return null;

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception("Failed to load ZanCrew state: ${res.body}");
    }

    final decoded = jsonDecode(res.body);

    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    return null;
  }

  // ---------------------------------------------------------------------------
  // 4) SET ONLINE (strict mode)
  //
  // Backend throws 403 with messages:
  // - Phone not verified
  // - No skills selected yet
  // - Bank verification incomplete
  // - KYC verification incomplete
  // - Profile is not active
  // ---------------------------------------------------------------------------

  static Future<bool> setOnline({
    required String userId,
    required bool online,
  }) async {
    final res = await _call(
      (h) => http.post(
        _u("/zancrew/set_online"),
        headers: h,
        body: jsonEncode({"user_id": userId, "online": online}),
      ),
    );

    if (res.statusCode == 403) {
      throw Exception(res.body.isNotEmpty ? res.body : "Permission denied");
    }

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception("Failed to set online: ${res.statusCode} ${res.body}");
    }

    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) {
      return decoded["online"] == true;
    }

    return false;
  }

  // ---------------------------------------------------------------------------
  // 5) DEV VERIFY — Flip backend KYC/BANK for testing
  // POST /zancrew/verify/dev/{bank|kyc}
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>> verifyDev(
    String userId, {
    required String type,
  }) async {
    assert(type == "bank" || type == "kyc");

    final res = await _call(
      (h) => http.post(
        _u("/zancrew/verify/dev/$type"),
        headers: h,
        body: jsonEncode({"user_id": userId}),
      ),
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception("DEV verify ($type) failed: ${res.body}");
    }

    final decoded = jsonDecode(res.body);

    if (decoded is Map<String, dynamic>) return decoded;

    throw Exception("Unexpected response: ${res.body}");
  }

  // ---------------------------------------------------------------------------
  // 6) CUSTOMER RATING FOR A JOB
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>> jobCustomerRating(String jobId) async {
    final res = await _call((h) => http.get(_u("/zancrew/tasks/$jobId/customer_rating"), headers: h));

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception("Failed to load rating: ${res.body}");
    }

    final decoded = jsonDecode(res.body);

    if (decoded is Map<String, dynamic>) {
      return Map<String, dynamic>.from(decoded);
    }

    throw Exception("Invalid rating response");
  }
}