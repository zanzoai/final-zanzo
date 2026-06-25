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
  // 1) UPSERT PROFILE  POST /zancrew/profile
  //    { buckets, radius_km, work_hours, home_latitude, home_longitude }
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>> upsertProfile({
    required List<String> buckets,
    required int radiusKm,
    String? workHours,
    double? homeLatitude,
    double? homeLongitude,
    // Legacy callers may still pass userId / status — accepted but not sent
    String? userId,
    String? status,
  }) async {
    final body = <String, dynamic>{
      "buckets": buckets.join(","),
      "radius_km": radiusKm,
      if (workHours != null) "work_hours": workHours,
      if (homeLatitude != null) "home_latitude": homeLatitude,
      if (homeLongitude != null) "home_longitude": homeLongitude,
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
  // 2) GET PROFILE  GET /zancrew/profile
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>?> getProfile([String? userId]) async {
    final res = await _call((h) => http.get(_u("/zancrew/profile"), headers: h));

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
  // 3) GET STATE  GET /zancrew/state
  //    Returns onboarding snapshot with onboarding_step, crew status, etc.
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>?> getState([String? userId]) async {
    final res = await _call((h) => http.get(_u("/zancrew/state"), headers: h));

    if (res.statusCode == 404) return null;
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception("Failed to load ZanCrew state: ${res.body}");
    }

    final decoded = jsonDecode(res.body);
    return (decoded is Map<String, dynamic>) ? decoded : null;
  }

  // ---------------------------------------------------------------------------
  // 4) SET ONLINE  POST /zancrew/set_online
  // ---------------------------------------------------------------------------

  static Future<bool> setOnline({
    required bool online,
    String? userId, // accepted for legacy callers, not sent to server
  }) async {
    final res = await _call(
      (h) => http.post(
        _u("/zancrew/set_online"),
        headers: h,
        body: jsonEncode({"online": online}),
      ),
    );

    if (res.statusCode == 403) {
      throw Exception(res.body.isNotEmpty ? res.body : "Permission denied");
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception("Failed to set online: ${res.statusCode} ${res.body}");
    }

    final decoded = jsonDecode(res.body);
    return (decoded is Map<String, dynamic>) ? decoded["online"] == true : false;
  }

  // ---------------------------------------------------------------------------
  // 5) SWITCH MODE  POST /zancrew/mode
  //    mode: "employee" | "user"
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>> switchMode(String mode) async {
    final res = await _call(
      (h) => http.post(
        _u("/zancrew/mode"),
        headers: h,
        body: jsonEncode({"mode": mode}),
      ),
    );

    if (res.statusCode == 403) {
      Map<String, dynamic>? err;
      try { err = jsonDecode(res.body) as Map<String, dynamic>?; } catch (_) {}
      throw Exception(err?['detail'] ?? "Mode switch denied (403)");
    }
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception("Failed to switch mode: ${res.statusCode} ${res.body}");
    }

    return Map<String, dynamic>.from(jsonDecode(res.body));
  }

  // ---------------------------------------------------------------------------
  // 6) BECOME CREW (non-UK)  POST /zancrew/become
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>> becomeCrew({
    required String buckets,
    required String radius,
    String? workHours,
    double? homeLatitude,
    double? homeLongitude,
  }) async {
    final body = <String, dynamic>{
      "buckets": buckets,
      "radius": radius,
      if (workHours != null) "work_hours": workHours,
      if (homeLatitude != null) "home_latitude": homeLatitude,
      if (homeLongitude != null) "home_longitude": homeLongitude,
    };

    final res = await _call(
      (h) => http.post(_u("/zancrew/become"), headers: h, body: jsonEncode(body)),
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      Map<String, dynamic>? err;
      try { err = jsonDecode(res.body) as Map<String, dynamic>?; } catch (_) {}
      throw Exception(err?['detail'] ?? "Crew application failed (${res.statusCode})");
    }

    return Map<String, dynamic>.from(jsonDecode(res.body));
  }

  // ---------------------------------------------------------------------------
  // 7) GET ACTIVE TASK — delegated to ApiService
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>?> getActiveTask() =>
      ApiService.getActiveTask();

  // ---------------------------------------------------------------------------
  // 8) GET TASK ASSIGNEE  GET /zancrew/tasks/{task_id}/assignee
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>> getTaskAssignee(String taskId) async {
    final res = await _call(
      (h) => http.get(_u("/zancrew/tasks/$taskId/assignee"), headers: h),
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception("Failed to load assignee: ${res.body}");
    }

    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) return decoded;
    throw Exception("Unexpected assignee payload");
  }

  // ---------------------------------------------------------------------------
  // 9) SUBMIT REVIEW  POST /zancrew/tasks/{task_id}/review
  //    Serves both crew→customer and customer→crew (same endpoint).
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>> submitReview({
    required String taskId,
    required int rating,
    String? comment,
  }) async {
    final body = <String, dynamic>{
      "rating": rating,
      if (comment != null && comment.trim().isNotEmpty) "comment": comment.trim(),
    };

    final res = await _call(
      (h) => http.post(
        _u("/zancrew/tasks/$taskId/review"),
        headers: h,
        body: jsonEncode(body),
      ),
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      Map<String, dynamic>? err;
      try { err = jsonDecode(res.body) as Map<String, dynamic>?; } catch (_) {}
      throw Exception(err?['detail'] ?? "Review submission failed (${res.statusCode})");
    }

    return Map<String, dynamic>.from(jsonDecode(res.body));
  }

  // ---------------------------------------------------------------------------
  // 10) GET TASK REVIEWS  GET /zancrew/tasks/{task_id}/reviews
  // ---------------------------------------------------------------------------

  static Future<List<Map<String, dynamic>>> getTaskReviews(String taskId) async {
    final res = await _call(
      (h) => http.get(_u("/zancrew/tasks/$taskId/reviews"), headers: h),
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception("Failed to load reviews: ${res.body}");
    }

    final decoded = jsonDecode(res.body);
    if (decoded is! List) throw Exception("Unexpected reviews payload");
    return decoded.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  // ---------------------------------------------------------------------------
  // 11) CUSTOMER RATING  GET /zancrew/tasks/{task_id}/customer_rating
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>> jobCustomerRating(String taskId) async {
    final res = await _call(
      (h) => http.get(_u("/zancrew/tasks/$taskId/customer_rating"), headers: h),
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception("Failed to load rating: ${res.body}");
    }

    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) return Map<String, dynamic>.from(decoded);
    throw Exception("Invalid rating response");
  }

  // ---------------------------------------------------------------------------
  // 12) USER RATING SUMMARY  GET /zancrew/users/{user_id}/rating_summary
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>> getUserRatingSummary(String userId) async {
    final res = await _call(
      (h) => http.get(_u("/zancrew/users/$userId/rating_summary"), headers: h),
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception("Failed to load rating summary: ${res.body}");
    }

    final decoded = jsonDecode(res.body);
    if (decoded is Map<String, dynamic>) return decoded;
    throw Exception("Unexpected rating summary payload");
  }

  // ---------------------------------------------------------------------------
  // 13) CONFIRM PAYMENT (crew COD)  POST /zancrew/confirm_payment
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>> confirmPayment({
    required String taskId,
    required String paymentId,
    required String orderId,
  }) async {
    final res = await _call(
      (h) => http.post(
        _u("/zancrew/confirm_payment"),
        headers: h,
        body: jsonEncode({
          "task_id": taskId,
          "payment_id": paymentId,
          "order_id": orderId,
        }),
      ),
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      Map<String, dynamic>? err;
      try { err = jsonDecode(res.body) as Map<String, dynamic>?; } catch (_) {}
      throw Exception(err?['detail'] ?? "Confirm payment failed (${res.statusCode})");
    }

    return Map<String, dynamic>.from(jsonDecode(res.body));
  }

  // ---------------------------------------------------------------------------
  // 14) DEV VERIFY  POST /zancrew/verify/dev/{bank|kyc}
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
}
