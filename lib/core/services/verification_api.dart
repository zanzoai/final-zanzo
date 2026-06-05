//This file handles all KYC flows: PAN, bank, Aadhaar, Selfie, Face Comaparsion and stores verification status locally + syncs it to the ZenCrew profile on the backend.

// lib/core/services/verification_api.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// Core services
import 'package:zanzo_frontend/core/services/api_service.dart';
import 'package:zanzo_frontend/core/services/zancrew_api.dart';

class VerificationApi {
  static Uri _u(String path) => Uri.parse('${ApiService.baseUrl}$path');

  static Future<Map<String, String>> get _h => ApiService.authHeaders();

  // ---------------------------------------------------------------------------
  // PAN VERIFICATION
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>> startKyc({
    required String userId,
    required String pan,
    required String fullName,
    required String dob,
  }) async {
    final res = await http.post(
      _u('/verification/idfy/pan/verify'),
      headers: await _h,
      body: jsonEncode({
        'user_id': userId,
        'pan_number': pan,
        'full_name': fullName,
        'dob': dob,
      }),
    );

    final body = _decode(res);

    if (res.statusCode >= 300) {
      return {
        'ok': false,
        'status_code': res.statusCode,
        'error': body is String ? body : jsonEncode(body),
      };
    }

    return (body is Map<String, dynamic>)
        ? body
        : {'ok': false, 'error': 'Unexpected response'};
  }

  // ---------------------------------------------------------------------------
  // BANK VERIFICATION
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>> startBank({
    required String userId,
    required String accountNumber,
    required String ifsc,
    String? name,
  }) async {
    final res = await http.post(
      _u('/verification/idfy/bank/verify'),
      headers: await _h,
      body: jsonEncode({
        'user_id': userId,
        'account_number': accountNumber,
        'ifsc': ifsc,
        if (name != null && name.trim().isNotEmpty) 'name': name.trim(),
      }),
    );

    final body = _decode(res);

    if (res.statusCode >= 300) {
      return {
        'ok': false,
        'status_code': res.statusCode,
        'error': body is String ? body : jsonEncode(body),
      };
    }

    return (body is Map<String, dynamic>)
        ? body
        : {'ok': false, 'error': 'Unexpected response'};
  }

  // ---------------------------------------------------------------------------
  // FETCH OVERALL VERIFICATION STATUS
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>> fetchStatus(String userId) async {
    final res = await http.get(_u('/verification/status/$userId'), headers: await _h);
    final body = _decode(res);

    if (res.statusCode >= 300) {
      throw Exception(
        'fetchStatus failed: ${res.statusCode} '
        '${body is String ? body : jsonEncode(body)}',
      );
    }

    return (body is Map<String, dynamic>)
        ? body
        : throw Exception('Unexpected status payload');
  }

  // ---------------------------------------------------------------------------
  // DEV VERIFICATION (LOCAL + BACKEND SYNC)
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>> devVerify({
    required String userId,
    required String type,
  }) async {
    assert(type == 'bank' || type == 'kyc');

    try {
      final res = await http.post(
        _u('/zancrew/verify/dev/$type'),
        headers: await _h,
        body: jsonEncode({'user_id': userId}),
      );

      final body = _decode(res);

      if (res.statusCode < 300 && body is Map<String, dynamic>) {
        await _persistLocalFlagsFromMap(body);
        await _bestEffortServerSync(userId, body);
        return body;
      }
    } catch (_) {
      // fall through to local mock
    }

    final prefs = await SharedPreferences.getInstance();

    bool bank = prefs.getBool('zancrew_bank_verified') ?? false;
    bool kyc = prefs.getBool('zancrew_kyc_verified') ?? false;

    if (type == 'bank') bank = true;
    if (type == 'kyc') kyc = true;

    final status = (bank && kyc) ? 'active' : 'pending';
    final enabled = status == 'active';

    await prefs.setBool('zancrew_bank_verified', bank);
    await prefs.setBool('zancrew_kyc_verified', kyc);
    await prefs.setString('zancrew_status', status);
    await prefs.setBool('zancrew_enabled', enabled);

    final result = {
      'bank_verified': bank,
      'kyc_verified': kyc,
      'status': status,
    };

    await _bestEffortServerSync(userId, result);
    return result;
  }

  // ---------------------------------------------------------------------------
  // UNIFIED VERIFICATION (PAN → BANK → AADHAAR → SELFIE)
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>> startUnified({
    required String userId,
    required String panNumber,
    required String fullName,
    required String dob,
    required String accountNumber,
    required String ifsc,
    String? aadhaarNumber,
    String? aadhaarFrontBase64,
    String? aadhaarBackBase64,
    String? selfieBase64,
    bool debugForceVerifyBodyFlag = false,
    bool debugForceVerifyHeader = false,
  }) async {
    final uri =
        Uri.parse('${ApiService.baseUrl}/verification/unified/run');

    final payload = {
      "user_id": userId,
      "pan_number": panNumber,
      "full_name": fullName,
      "dob": dob,
      "account_number": accountNumber,
      "ifsc": ifsc,
      if (aadhaarNumber != null && aadhaarNumber.isNotEmpty)
        "aadhaar_number": aadhaarNumber,
      if (aadhaarFrontBase64 != null) "aadhaar_front_base64": aadhaarFrontBase64,
      if (aadhaarBackBase64 != null) "aadhaar_back_base64": aadhaarBackBase64,
      if (selfieBase64 != null) "selfie_base64": selfieBase64,
      if (debugForceVerifyBodyFlag) "debug_force_verify": true,
    };

    print("📤 Unified verification payload: $payload");

    final headers = {
      ...await _h,
      if (debugForceVerifyHeader) "X-Debug-Force-Verify": "true",
    };

    final res = await http.post(
      uri,
      headers: headers,
      body: jsonEncode(payload),
    );

    if (res.statusCode >= 300) {
      throw Exception("Unified verification failed: ${res.body}");
    }

    final decoded = jsonDecode(res.body);
    print("✅ Unified verification response: $decoded");

    return decoded as Map<String, dynamic>;
  }

  // ---------------------------------------------------------------------------
  // INTERNAL HELPERS
  // ---------------------------------------------------------------------------

  static dynamic _decode(http.Response res) {
    try {
      return jsonDecode(res.body);
    } catch (_) {
      return res.body;
    }
  }

  static Future<void> _persistLocalFlagsFromMap(
      Map<String, dynamic> m) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(
      'zancrew_bank_verified',
      (m['bank_verified'] as bool?) ?? false,
    );
    await prefs.setBool(
      'zancrew_kyc_verified',
      (m['kyc_verified'] as bool?) ?? false,
    );
    await prefs.setString(
      'zancrew_status',
      (m['status'] as String?) ?? 'pending',
    );
    await prefs.setBool(
      'zancrew_enabled',
      ((m['status'] as String?) ?? 'pending') == 'active',
    );
  }

  static Future<void> _bestEffortServerSync(
    String userId,
    Map<String, dynamic> flags,
  ) async {
    try {
      final profile = await ZanCrewApi.getProfile(userId);
      final buckets = (profile?['buckets'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [];

      final radiusKm =
          (profile?['radius_km'] as num?)?.toInt() ?? 5;

      await ZanCrewApi.upsertProfile(
        userId: userId,
        buckets: buckets,
        radiusKm: radiusKm,
        status: (flags['status'] as String?) ?? 'pending',
      );
    } catch (_) {
      // ignore error—best effort only
    }
  }
}