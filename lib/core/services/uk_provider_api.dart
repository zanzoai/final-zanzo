// lib/core/services/uk_provider_api.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class UkProviderApi {
  static String get _base => ApiService.baseUrl;

  static Future<Map<String, dynamic>?> getStatus(String userId) async {
    final res = await ApiService.callWithRefresh(
      (h) => http.get(Uri.parse('$_base/uk/provider/status/$userId'), headers: h),
    );
    if (res.statusCode == 404) return null;
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to get UK provider status: ${res.statusCode}');
  }

  static Future<Map<String, dynamic>> apply({
    required String userId,
    required String declaredWorkStatus,
    required String fullName,
    String? dateOfBirth,
    String? phone,
    String? addressOrPostcode,
    String? shareCode,
    required bool termsAgreed,
    String? universityName,
    String? courseName,
    String? visaExpiryDate,
    String? applicantNotes,
  }) async {
    final body = <String, dynamic>{
      'user_id': userId,
      'declared_work_status': declaredWorkStatus,
      'full_name': fullName,
      'terms_agreed': termsAgreed,
    };
    if (dateOfBirth != null) body['date_of_birth'] = dateOfBirth;
    if (phone != null) body['phone'] = phone;
    if (addressOrPostcode != null) body['address_or_postcode'] = addressOrPostcode;
    if (shareCode != null) body['share_code'] = shareCode;
    if (universityName != null) body['university_name'] = universityName;
    if (courseName != null) body['course_name'] = courseName;
    if (visaExpiryDate != null) body['visa_expiry_date'] = visaExpiryDate;
    if (applicantNotes != null) body['applicant_notes'] = applicantNotes;

    final res = await ApiService.callWithRefresh(
      (h) => http.post(
        Uri.parse('$_base/uk/provider/apply'),
        headers: h,
        body: jsonEncode(body),
      ),
    );

    if (res.statusCode == 200 || res.statusCode == 201) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    final err = jsonDecode(res.body) as Map<String, dynamic>?;
    throw Exception(err?['detail'] ?? 'Application failed (${res.statusCode})');
  }

  static Future<Map<String, dynamic>> uploadDocument({
    required String documentType,
    required File file,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    if (token == null || token.isEmpty) throw Exception('Not signed in');

    final uri = Uri.parse('$_base/uk/provider/documents/upload')
        .replace(queryParameters: {'document_type': documentType});

    final req = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..files.add(await http.MultipartFile.fromPath('file', file.path));

    final streamed = await req.send();
    final res = await http.Response.fromStream(streamed);

    if (res.statusCode == 200 || res.statusCode == 201) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    Map<String, dynamic>? err;
    try {
      err = jsonDecode(res.body) as Map<String, dynamic>?;
    } catch (_) {}
    throw Exception(err?['detail'] ?? 'Upload failed (${res.statusCode})');
  }
}
