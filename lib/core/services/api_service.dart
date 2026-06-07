// lib/core/services/api_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  /// Backend base URL (Production — Railway)
  //static const String baseUrl = "https://zanzo-uk-mvp-production.up.railway.app";

  // static const String baseUrl =
  //     "https://zanzo-uk-backend-production-4236.up.railway.app";

  // static const String baseUrl =
  //     "https://zanzo-uk-backend-production.up.railway.app/api/v1";

  static const String baseUrl =
      "https://zanzo-uk-backend-production-b2d0.up.railway.app/api/v1";

  /// Backend base URL (LAN/IP for local device testing)
  // static const String baseUrl = "http://192.168.193.93:8000";

  /// Shared HTTP client
  static final http.Client httpClient = http.Client();

  /// Common JSON headers
  static Map<String, String> get jsonHeaders => const {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };

  // ---------------------------------------------------------------------------
  // INTERNAL HELPERS
  // ---------------------------------------------------------------------------

  static Uri _u(String path) => Uri.parse('$baseUrl$path');

  /// Returns JSON headers merged with Authorization if an access_token exists.
  static Future<Map<String, String>> authHeaders() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    if (token == null || token.isEmpty) return jsonHeaders;
    return {...jsonHeaders, 'Authorization': 'Bearer $token'};
  }

  static void _log(String tag, Object msg) {
    // ignore: avoid_print
    print('[API][$tag] $msg');
  }

  static String _truncate(Object o, {int max = 800}) {
    final s = o.toString();
    return (s.length <= max) ? s : '${s.substring(0, max)}…';
  }

  static Future<http.Response> _get(
    Uri url, {
    Duration timeout = const Duration(seconds: 12),
    Map<String, String>? headers,
  }) {
    _log('GET', url);
    return httpClient
        .get(url, headers: headers ?? jsonHeaders)
        .timeout(timeout);
  }

  static Future<http.Response> _post(
    Uri url,
    Object body, {
    Duration timeout = const Duration(seconds: 12),
    Map<String, String>? headers,
  }) {
    final payload = body is String ? body : jsonEncode(body);
    _log('POST', '$url payload=$payload');

    return httpClient
        .post(url, headers: headers ?? jsonHeaders, body: payload)
        .timeout(timeout);
  }

  // ---------------------------------------------------------------------------
  // HEALTH CHECK
  // ---------------------------------------------------------------------------

  static Future<bool> health() async {
    final url = _u('/health');
    try {
      final res = await _get(url, timeout: const Duration(seconds: 5));
      _log('health', 'status=${res.statusCode} body=${_truncate(res.body)}');
      return res.statusCode == 200;
    } on TimeoutException {
      _log('health', '❌ timeout');
      return false;
    } on SocketException catch (e) {
      _log('health', '❌ socket: $e');
      return false;
    } catch (e) {
      _log('health', '❌ error: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // PROCESS TASK
  // ---------------------------------------------------------------------------

  static Future<Map<String, dynamic>?> processTask({
    required String userInput,
    required double latitude,
    required double longitude,
  }) async {
    final url = _u('/tasks/process');
    final payload = {
      'user_input': userInput,
      'latitude': latitude,
      'longitude': longitude,
    };

    // ignore: avoid_print
    print('[API][process_task] baseUrl=$baseUrl');
    // ignore: avoid_print
    print('[API][process_task] POST $url');
    // ignore: avoid_print
    print('[API][process_task] body=${jsonEncode(payload)}');

    try {
      final res = await _post(
        url,
        payload,
        headers: await authHeaders(),
        timeout: const Duration(seconds: 40),
      );

      // ignore: avoid_print
      print('[API][process_task] ← status=${res.statusCode}');
      // ignore: avoid_print
      print('[API][process_task] ← body=${_truncate(res.body)}');

      if (res.statusCode != 200) {
        _log(
          'process_task',
          '❌ HTTP ${res.statusCode}: ${_truncate(res.body)}',
        );
        String detail = 'HTTP ${res.statusCode}';
        try {
          final body = jsonDecode(res.body);
          if (body is Map) {
            detail =
                body['detail']?.toString() ??
                body['message']?.toString() ??
                body['error']?.toString() ??
                detail;
          }
        } catch (_) {}
        return {
          "ok": false,
          "error_type": "server_error",
          "status_code": res.statusCode,
          "user_message": detail,
        };
      }

      final decoded = jsonDecode(res.body);

      // Backend ok=false → pass through as-is
      if (decoded is Map<String, dynamic> && decoded["ok"] == false) {
        return decoded;
      }

      return (decoded is Map<String, dynamic>) ? decoded : null;
    } on TimeoutException {
      // ignore: avoid_print
      print('[API][process_task] ❌ TIMEOUT after 40s');
      return {
        "ok": false,
        "error_type": "timeout",
        "user_message": "Request timed out after 40 s. Please try again.",
      };
    } on SocketException catch (e) {
      // ignore: avoid_print
      print('[API][process_task] ❌ SOCKET ERROR: $e');
      return {
        "ok": false,
        "error_type": "network",
        "user_message": e.message.isNotEmpty
            ? e.message
            : "No internet connection.",
      };
    } catch (e, st) {
      _log('process_task', '❌ error: $e\n$st');
      return {
        "ok": false,
        "error_type": "unknown_error",
        "user_message": e.toString(),
      };
    }
  }
  // ---------------------------------------------------------------------------
  // JOB EVENTS
  // ---------------------------------------------------------------------------

  static Future<void> postJobEvent(
    String jobId,
    String status,
    String note,
    String crewUserId,
  ) async {
    final url = Uri.parse('$baseUrl/zancrew/tasks/$jobId/events');

    final payload = {
      "status": status,
      "note": note,
      "crew_user_id": crewUserId,
    };

    final res = await http.post(
      url,
      headers: await authHeaders(),
      body: jsonEncode(payload),
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception(
        'POST /zancrew/tasks/$jobId/events failed (${res.statusCode}): ${res.body}',
      );
    }
  }

  static Future<http.Response> getJob(String jobId) {
    return _get(_u('/tasks/$jobId'));
  }

  static Future<Map<String, dynamic>> getJobSession(String jobId) async {
    final res = await _get(_u('/tasks/$jobId/otp'));
    if (res.statusCode != 200) {
      throw HttpException(
        'GET /tasks/$jobId/otp failed: ${res.statusCode} ${res.body}',
      );
    }
    return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
  }

  static Future<Map<String, dynamic>> getSessionSummary(String jobId) async {
    return {};
  }

  static Future<void> postSessionStart(String jobId, String pin) async {
    final res = await _post(_u('/tasks/$jobId/verify-start-otp'), {"otp": pin});
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw HttpException(
        'POST /tasks/$jobId/verify-start-otp failed: '
        '${res.statusCode} ${_truncate(res.body)}',
      );
    }
  }

  static Future<void> postSessionEnd(String jobId, String pin) async {
    final res = await _post(_u('/tasks/$jobId/verify-end-otp'), {"otp": pin});
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw HttpException(
        'POST /tasks/$jobId/verify-end-otp failed: '
        '${res.statusCode} ${_truncate(res.body)}',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // ZANCREW — OFFERS
  // ---------------------------------------------------------------------------

  static Future<List<Map<String, dynamic>>> fetchCrewOffers({
    required String crewUserId,
    String status = 'offered',
    int limit = 20,
  }) async {
    final url = Uri.parse('$baseUrl/zancrew/offers').replace(
      queryParameters: {
        'status': status,
        'limit': '$limit',
      },
    );

    final res = await _get(url, headers: await authHeaders());
    if (res.statusCode != 200) {
      throw HttpException(
        'GET /zancrew/offers failed: ${res.statusCode} ${_truncate(res.body)}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(res.body);
    } catch (e) {
      throw HttpException('GET /zancrew/offers JSON decode failed: $e');
    }

    if (decoded is! List) {
      throw const HttpException('Unexpected offers payload shape');
    }

    _log('offers.raw', _truncate(res.body, max: 500));

    final list = decoded.map<Map<String, dynamic>>((raw) {
      final m = Map<String, dynamic>.from(raw as Map);
      final offerId = (m['offer_id'] ?? m['id'])?.toString() ?? '';
      final statusNorm =
          (m['status'] ?? m['offer_status'])?.toString().toLowerCase() ??
          'offered';

      m['offer_id'] = offerId;
      m['status'] = statusNorm;
      return m;
    }).toList();

    for (final m in list) {
      _log(
        'offer.distance',
        'offer_id=${m['offer_id']} '
            'distance_km=${m['distance_km']} '
            'lat=${m['latitude']} lng=${m['longitude']}',
      );
    }

    return list;
  }

  static Future<http.Response> getOfferDetail(String offerId) async {
    final res = await _get(_u('/zancrew/offers/$offerId'), headers: await authHeaders());
    _log('offer.detail', 'id=$offerId body=${_truncate(res.body, max: 600)}');
    return res;
  }

  static Future<Map<String, dynamic>> acceptOffer(String offerId) async {
    final res = await _post(_u('/zancrew/offers/$offerId/accept'), {}, headers: await authHeaders());
    if (res.statusCode != 200) {
      throw HttpException(
        'POST /zancrew/offers/{id}/accept failed: '
        '${res.statusCode} ${_truncate(res.body)}',
      );
    }
    return Map<String, dynamic>.from(jsonDecode(res.body));
  }

  static Future<Map<String, dynamic>> rejectOffer(String offerId) async {
    final res = await _post(_u('/zancrew/offers/$offerId/reject'), {}, headers: await authHeaders());
    if (res.statusCode != 200) {
      throw HttpException(
        'POST /zancrew/offers/{id}/reject failed: '
        '${res.statusCode} ${_truncate(res.body)}',
      );
    }
    return Map<String, dynamic>.from(jsonDecode(res.body));
  }

  // ---------------------------------------------------------------------------
  // ZANCREW — MY JOBS
  // ---------------------------------------------------------------------------

  static Future<List<Map<String, dynamic>>> fetchCrewMyJobs({
    required String crewUserId,
    int limit = 20,
  }) async {
    final url = Uri.parse(
      '$baseUrl/zancrew/history',
    ).replace(queryParameters: {'limit': '$limit'});

    final res = await _get(url, headers: await authHeaders());
    if (res.statusCode != 200) {
      throw HttpException(
        'GET /zancrew/history failed: ${res.statusCode} ${_truncate(res.body)}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(res.body);
    } catch (e) {
      throw HttpException('GET /zancrew/history JSON decode failed: $e');
    }

    final taskList = (decoded is Map) ? decoded['tasks'] : decoded;
    if (taskList is! List) {
      throw const HttpException('Unexpected history payload shape');
    }

    return taskList.map<Map<String, dynamic>>((e) {
      final m = Map<String, dynamic>.from(e as Map);
      m['job_id'] = (m['task_id'] ?? '').toString();
      m['status'] = (m['status'] ?? '').toString().toLowerCase();
      return m;
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // CREW LOCATION UPDATE
  // ---------------------------------------------------------------------------

  static Future<bool> postCrewLocationUpdate({
    required String crewUserId,
    required double lat,
    required double lng,
  }) async {
    final payload = {'lat': lat, 'lng': lng};

    try {
      final res = await _post(
        _u('/zancrew/crew_location/update'),
        payload,
        headers: await authHeaders(),
        timeout: const Duration(seconds: 8),
      );

      if (res.statusCode == 200) {
        _log('crew_location', '✅ updated for $crewUserId @ $lat,$lng');
        return true;
      }

      _log('crew_location', '❌ HTTP ${res.statusCode}: ${_truncate(res.body)}');
      return false;
    } catch (e) {
      _log('crew_location', '❌ error: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // AUTH (EMAIL + PHONE)
  // ---------------------------------------------------------------------------

  // POST /auth/auth/send-email-otp  →  { name?, email }
  static Future<http.Response> sendEmailOtp(String email, {String? name}) {
    return _post(_u('/auth/send-email-otp'), {
      'email': email.trim(),
      if (name != null) 'name': name.trim(),
    });
  }

  // POST /auth/verify-email-otp  →  { email, otp }
  static Future<http.Response> verifyEmailOtp(String email, String otp) {
    return _post(_u('/auth/verify-email-otp'), {
      'email': email.trim(),
      'otp': otp.trim(),
    });
  }

  // POST /auth/send-phone-otp  →  { phone }
  static Future<http.Response> sendPhoneOtp(String phoneE164) {
    return _post(_u('/auth/send-phone-otp'), {'phone': phoneE164.trim()});
  }

  // POST /auth/auth/verify-phone-otp  →  { phone, code }
  // Stores access_token, refresh_token, user_id, user_phone, user_role in prefs.
  static Future<bool> verifyPhoneOtp(String phoneE164, String code) async {
    final res = await _post(_u('/auth/verify-phone-otp'), {
      'phone': phoneE164.trim(),
      'code': code.trim(),
    });

    if (res.statusCode < 200 || res.statusCode >= 300) {
      _log(
        'verifyPhoneOtp',
        '❌ HTTP ${res.statusCode}: ${_truncate(res.body)}',
      );
      return false;
    }

    try {
      final Map<String, dynamic> body = jsonDecode(res.body);
      final prefs = await SharedPreferences.getInstance();

      final access = body['access_token']?.toString();
      final refresh = body['refresh_token']?.toString();
      final user = (body['user'] is Map)
          ? Map<String, dynamic>.from(body['user'])
          : null;

      final userId = user?['id']?.toString();
      final phoneOut = user?['phone']?.toString() ?? phoneE164;
      final role = user?['role']?.toString() ?? 'user';

      if (access != null && access.isNotEmpty) {
        await prefs.setString('access_token', access);
      }
      if (refresh != null && refresh.isNotEmpty) {
        await prefs.setString('refresh_token', refresh);
      }
      if (userId != null && userId.isNotEmpty) {
        await prefs.setString('user_id', userId);
      }

      await prefs.setString('user_phone', phoneOut);
      await prefs.setBool('phone_verified', true);
      await prefs.setString('user_role', role);

      _log(
        'verifyPhoneOtp',
        '✅ login ok user_id=$userId phone=$phoneOut role=$role',
      );
      return true;
    } catch (e, st) {
      _log('verifyPhoneOtp', '❌ parse/save failed: $e\n$st');
      return false;
    }
  }

  // POST /auth/refresh  →  { refresh_token }
  // Returns a new TokenPair and updates stored tokens.
  static Future<bool> refreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshTok = prefs.getString('refresh_token');
    if (refreshTok == null || refreshTok.isEmpty) {
      _log('refreshToken', '⚠️ no refresh_token stored');
      return false;
    }

    try {
      final res = await _post(_u('/auth/refresh'), {
        'refresh_token': refreshTok,
      }, timeout: const Duration(seconds: 15));

      if (res.statusCode < 200 || res.statusCode >= 300) {
        _log('refreshToken', '❌ HTTP ${res.statusCode}');
        return false;
      }

      final body = jsonDecode(res.body) as Map<String, dynamic>;
      final access = body['access_token']?.toString();
      final refresh = body['refresh_token']?.toString();

      if (access != null && access.isNotEmpty) {
        await prefs.setString('access_token', access);
      }
      if (refresh != null && refresh.isNotEmpty) {
        await prefs.setString('refresh_token', refresh);
      }

      _log('refreshToken', '✅ tokens refreshed');
      return true;
    } catch (e, st) {
      _log('refreshToken', '❌ error: $e\n$st');
      return false;
    }
  }

  // POST /auth/logout  →  { refresh_token }  (requires Bearer token)
  // Invalidates the refresh token on the server.
  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    final access = prefs.getString('access_token');
    final refresh = prefs.getString('refresh_token');

    if (access == null || refresh == null) return;

    try {
      await httpClient
          .post(
            _u('/auth/logout'),
            headers: {...jsonHeaders, 'Authorization': 'Bearer $access'},
            body: jsonEncode({'refresh_token': refresh}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      _log('logout', '⚠️ server logout failed (ignored): $e');
    }
  }

  // GET /auth/me  (requires Bearer token)
  // Returns the current user's profile as a Map, or null on failure.
  static Future<Map<String, dynamic>?> getMe() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    if (token == null || token.isEmpty) return null;

    try {
      final res = await httpClient
          .get(
            _u('/auth/me'),
            headers: {...jsonHeaders, 'Authorization': 'Bearer $token'},
          )
          .timeout(const Duration(seconds: 12));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      _log('getMe', '❌ HTTP ${res.statusCode}');
      return null;
    } catch (e) {
      _log('getMe', '❌ error: $e');
      return null;
    }
  }

  // PATCH /auth/me  →  { full_name?, password? }  (requires Bearer token)
  // Updates the current user's profile.
  static Future<Map<String, dynamic>?> updateProfile({
    String? fullName,
    String? password,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    if (token == null || token.isEmpty) return null;

    final payload = <String, dynamic>{
      if (fullName != null) 'full_name': fullName.trim(),
      if (password != null) 'password': password,
    };

    try {
      final res = await httpClient
          .patch(
            _u('/auth/me'),
            headers: {...jsonHeaders, 'Authorization': 'Bearer $token'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 12));

      if (res.statusCode == 200) {
        return jsonDecode(res.body) as Map<String, dynamic>;
      }
      _log('updateProfile', '❌ HTTP ${res.statusCode}: ${_truncate(res.body)}');
      return null;
    } catch (e) {
      _log('updateProfile', '❌ error: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // GENERIC (POST JSON / GET JSON)
  // ---------------------------------------------------------------------------

  static Future<http.Response> postJson(
    String path,
    Map<String, dynamic> body, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final base = await authHeaders();
    final merged = {...base, if (headers != null) ...headers};
    final url = _u(path);
    _log('postJson', 'POST $url payload=${jsonEncode(body)}');

    return httpClient
        .post(url, headers: merged, body: jsonEncode(body))
        .timeout(timeout);
  }

  static Future<http.Response> getJson(
    String path, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 12),
  }) async {
    final base = await authHeaders();
    final merged = {...base, if (headers != null) ...headers};
    final url = _u(path);
    _log('getJson', 'GET $url');

    return httpClient.get(url, headers: merged).timeout(timeout);
  }

  // ---------------------------------------------------------------------------
  // UPDATE EMAIL / PHONE
  // ---------------------------------------------------------------------------

  static Future<bool> updateEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    if (token == null || token.isEmpty) return false;

    final res = await httpClient.post(
      Uri.parse('$baseUrl/auth/set-email'),
      headers: {...jsonHeaders, 'Authorization': 'Bearer $token'},
      body: jsonEncode({'email': email.trim()}),
    );

    if (res.statusCode >= 200 && res.statusCode < 300) {
      await prefs.setString('user_email', email.trim());
      return true;
    }

    return false;
  }

  static Future<http.Response> sendUpdatePhoneOtp(String newPhone) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');

    if (token == null || token.isEmpty) {
      throw Exception("Missing access token");
    }

    return httpClient.post(
      Uri.parse('$baseUrl/auth/update-phone/send'),
      headers: {...jsonHeaders, 'Authorization': 'Bearer $token'},
      body: jsonEncode({'new_phone': newPhone.trim()}),
    );
  }

  static Future<http.Response> verifyUpdatePhoneOtp(
    String newPhone,
    String code,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');

    if (token == null || token.isEmpty) {
      throw Exception("Missing access token");
    }

    final res = await httpClient.post(
      Uri.parse('$baseUrl/auth/update-phone/verify'),
      headers: {...jsonHeaders, 'Authorization': 'Bearer $token'},
      body: jsonEncode({'new_phone': newPhone.trim(), 'code': code.trim()}),
    );

    if (res.statusCode >= 200 && res.statusCode < 300) {
      try {
        final Map<String, dynamic> body = jsonDecode(res.body);
        final newToken = body['access_token']?.toString();
        final user = (body['user'] is Map)
            ? Map<String, dynamic>.from(body['user'])
            : null;

        final userId = user?['id']?.toString();
        final phoneOut = user?['phone']?.toString() ?? newPhone;
        final role = user?['role']?.toString();

        if (newToken != null && newToken.isNotEmpty) {
          await prefs.setString('access_token', newToken);
        }
        if (userId != null && userId.isNotEmpty) {
          await prefs.setString('user_id', userId);
        }

        await prefs.setString('user_phone', phoneOut);
        await prefs.setBool('phone_verified', true);

        if (role != null && role.isNotEmpty) {
          await prefs.setString('user_role', role);
        }
      } catch (e) {
        _log('verifyUpdatePhoneOtp', '⚠️ JSON parse/save failed: $e');
      }
    }

    return res;
  }

  // ---------------------------------------------------------------------------
  // DEVICE TOKEN — FCM REGISTRATION
  // ---------------------------------------------------------------------------

  static Future<bool> registerDeviceToken({
    required String token,
    required String platform,
    String? appVersion,
    String? deviceId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final accessToken = prefs.getString('access_token');
    if (accessToken == null || accessToken.isEmpty) {
      _log('fcm', '⚠️ registerDeviceToken skipped — no access_token');
      return false;
    }

    final prefix = token.length >= 8 ? token.substring(0, 8) : '???';
    _log('fcm', 'registering token=$prefix… platform=$platform');

    try {
      final body = <String, dynamic>{
        'token': token,
        'platform': platform,
        if (appVersion != null) 'app_version': appVersion,
        if (deviceId != null) 'device_id': deviceId,
      };

      final res = await httpClient
          .post(
            _u('/device-tokens/register'),
            headers: {...jsonHeaders, 'Authorization': 'Bearer $accessToken'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));

      if (res.statusCode >= 200 && res.statusCode < 300) {
        _log('fcm', '✅ token registered');
        return true;
      }
      _log(
        'fcm',
        '❌ register failed HTTP ${res.statusCode}: ${_truncate(res.body)}',
      );
      return false;
    } catch (e) {
      _log('fcm', '❌ register error: $e');
      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // PROFILE PHOTO UPLOAD
  // ---------------------------------------------------------------------------

  static Future<String?> uploadProfilePhoto(File file) async {
    const int maxBytes = 2 * 1024 * 1024;

    final len = await file.length();
    if (len > maxBytes) {
      throw Exception("Image too large (> 2 MB). Please pick a smaller photo.");
    }

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');

    if (token == null || token.isEmpty) {
      throw Exception("Missing access token");
    }

    final uri = Uri.parse('$baseUrl/profile/photo/upload');
    final req = http.MultipartRequest('POST', uri)
      ..headers.addAll({'Authorization': 'Bearer $token'})
      ..files.add(await http.MultipartFile.fromPath('file', file.path));

    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);

    if (res.statusCode >= 200 && res.statusCode < 300) {
      try {
        final Map<String, dynamic> body = jsonDecode(res.body);
        final url = body['url']?.toString();

        if (url != null && url.isNotEmpty) {
          await prefs.setString('profile_photo_url', url);
        }

        return url;
      } catch (_) {
        // ignore
      }
    }

    throw HttpException(
      'Upload failed: ${res.statusCode} ${_truncate(res.body)}',
    );
  }

  // ---------------------------------------------------------------------------
  // UTILS
  // ---------------------------------------------------------------------------

  static String wsBaseUrl(String path) {
    final uri = Uri.parse(baseUrl);
    final wsScheme = uri.scheme == "https" ? "wss" : "ws";
    return "$wsScheme://${uri.host}:${uri.port}$path";
  }

  static Map<String, dynamic> safeJsonDecode(dynamic data) {
    try {
      return Map<String, dynamic>.from(jsonDecode(data));
    } catch (_) {
      return {};
    }
  }
}
