// lib/core/services/uk_provider_api.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'api_service.dart';
import 'package:zanzo_frontend/core/services/token_store.dart';

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
    String? courseLevel,
    String? visaExpiryDate,
    int? otherEmploymentHoursPerWeek,
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
    if (courseLevel != null) body['course_level'] = courseLevel;
    if (visaExpiryDate != null) body['visa_expiry_date'] = visaExpiryDate;
    if (otherEmploymentHoursPerWeek != null) {
      body['other_employment_hours_per_week'] = otherEmploymentHoursPerWeek;
    }
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

  /// Infer a [MediaType] from a file path extension.
  static MediaType _mediaTypeFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return MediaType('image', 'png');
    if (lower.endsWith('.pdf')) return MediaType('application', 'pdf');
    if (lower.endsWith('.docx')) {
      return MediaType('application',
          'vnd.openxmlformats-officedocument.wordprocessingml.document');
    }
    if (lower.endsWith('.doc')) return MediaType('application', 'msword');
    return MediaType('image', 'jpeg');
  }

  static Future<Map<String, dynamic>> uploadDocument({
    required String documentType,
    required File file,
  }) async {
    final token = await TokenStore.accessToken();
    if (token == null || token.isEmpty) throw Exception('Not signed in');

    final uri = Uri.parse('$_base/uk/provider/documents/upload')
        .replace(queryParameters: {'document_type': documentType});

    final mediaType = _mediaTypeFor(file.path);

    final req = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer $token'
      ..files.add(await http.MultipartFile.fromPath(
        'file',
        file.path,
        contentType: mediaType,
      ));

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

  static Future<Map<String, dynamic>> getBankDetails() async {
    final res = await ApiService.callWithRefresh(
      (h) => http.get(Uri.parse('$_base/uk/bank-details'), headers: h),
    );
    if (res.statusCode == 200) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to get bank details (${res.statusCode})');
  }

  static Future<Map<String, dynamic>> submitVacationRequest({
    required String startDate,
    required String endDate,
    String? documentKey,
  }) async {
    final body = <String, dynamic>{
      'start_date': startDate,
      'end_date': endDate,
      if (documentKey != null) 'document_key': documentKey,
    };
    final res = await ApiService.callWithRefresh(
      (h) => http.post(
        Uri.parse('$_base/uk/provider/vacation-request'),
        headers: h,
        body: jsonEncode(body),
      ),
    );
    if (res.statusCode == 200 || res.statusCode == 201) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    Map<String, dynamic>? err;
    try {
      err = jsonDecode(res.body) as Map<String, dynamic>?;
    } catch (_) {}
    throw Exception(err?['detail'] ?? 'Failed to submit vacation request (${res.statusCode})');
  }

  static Future<List<Map<String, dynamic>>> getVacationRequests() async {
    final res = await ApiService.callWithRefresh(
      (h) => http.get(Uri.parse('$_base/uk/provider/vacation-requests'), headers: h),
    );
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      if (data is List) return List<Map<String, dynamic>>.from(data);
      return [];
    }
    throw Exception('Failed to get vacation requests (${res.statusCode})');
  }

  static Future<Map<String, dynamic>> saveBankDetails({
    required String accountHolderName,
    required String sortCode,
    required String accountNumber,
    String? bankName,
  }) async {
    final body = <String, dynamic>{
      'account_holder_name': accountHolderName,
      'sort_code': sortCode,
      'account_number': accountNumber,
      'details_confirmed': true,
      if (bankName != null && bankName.isNotEmpty) 'bank_name': bankName,
    };
    final res = await ApiService.callWithRefresh(
      (h) => http.post(
        Uri.parse('$_base/uk/bank-details'),
        headers: h,
        body: jsonEncode(body),
      ),
    );
    if (res.statusCode == 200 || res.statusCode == 201) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    Map<String, dynamic>? err;
    try {
      err = jsonDecode(res.body) as Map<String, dynamic>?;
    } catch (_) {}
    throw Exception(err?['detail'] ?? 'Failed to save bank details (${res.statusCode})');
  }
}
