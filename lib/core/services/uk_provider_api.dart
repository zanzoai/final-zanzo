// lib/core/services/uk_provider_api.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';

class UkProviderApi {
  static String get _base => ApiService.baseUrl;

  static Future<String?> _token() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token');
  }

  static Future<Map<String, dynamic>?> getStatus(String userId) async {
    final token = await _token();
    final res = await http.get(
      Uri.parse('$_base/uk/provider/status/$userId'),
      headers: {
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
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
    String? niNumber,
    // Student-visa fields
    String? universityName,
    String? courseName,
    String? courseLevel,
    String? visaExpiryDate,
    int? otherEmploymentHoursPerWeek,
    String? applicantNotes,
    required bool termsAgreed,
  }) async {
    final token = await _token();
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
    if (niNumber != null && niNumber.isNotEmpty) body['ni_number'] = niNumber;
    if (universityName != null && universityName.isNotEmpty) body['university_name'] = universityName;
    if (courseName != null && courseName.isNotEmpty) body['course_name'] = courseName;
    if (courseLevel != null) body['course_level'] = courseLevel;
    if (visaExpiryDate != null && visaExpiryDate.isNotEmpty) body['visa_expiry_date'] = visaExpiryDate;
    if (otherEmploymentHoursPerWeek != null) body['other_employment_hours_per_week'] = otherEmploymentHoursPerWeek;
    if (applicantNotes != null && applicantNotes.isNotEmpty) body['applicant_notes'] = applicantNotes;

    final res = await http.post(
      Uri.parse('$_base/uk/provider/apply'),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );

    if (res.statusCode == 200 || res.statusCode == 201) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    final err = jsonDecode(res.body) as Map<String, dynamic>?;
    throw Exception(err?['detail'] ?? 'Application failed (${res.statusCode})');
  }

  /// Upload a provider document (e.g. term_time_evidence, passport_photo, selfie).
  /// Throws on failure; returns normally on success.
  static Future<void> uploadDocument({
    required File file,
    required String documentType,
  }) async {
    const int maxBytes = 10 * 1024 * 1024; // 10 MB limit (matches backend)
    final len = await file.length();
    if (len > maxBytes) {
      throw Exception('File too large (> 10 MB). Please choose a smaller file.');
    }

    final token = await _token();
    if (token == null || token.isEmpty) {
      throw Exception('Not signed in — please log in again.');
    }

    final uri = Uri.parse('$_base/uk/provider/documents/upload')
        .replace(queryParameters: {'document_type': documentType});

    final req = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..files.add(await http.MultipartFile.fromPath('file', file.path));

    final streamed = await req.send().timeout(const Duration(seconds: 30));
    final res = await http.Response.fromStream(streamed);

    if (res.statusCode >= 200 && res.statusCode < 300) return;

    final err = jsonDecode(res.body) as Map<String, dynamic>?;
    throw Exception(err?['detail'] ?? 'Document upload failed (${res.statusCode})');
  }
}
