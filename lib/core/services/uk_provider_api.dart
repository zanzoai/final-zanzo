// lib/core/services/uk_provider_api.dart
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_service.dart';

class UkProviderApi {
  static String get _base => ApiService.baseUrl;

  static Future<Map<String, dynamic>?> getStatus(String userId) async {
    final res = await http.get(
      Uri.parse('$_base/uk/provider/status/$userId'),
      headers: await ApiService.authHeaders(),
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

    final res = await http.post(
      Uri.parse('$_base/uk/provider/apply'),
      headers: await ApiService.authHeaders(),
      body: jsonEncode(body),
    );

    if (res.statusCode == 200 || res.statusCode == 201) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    final err = jsonDecode(res.body) as Map<String, dynamic>?;
    throw Exception(err?['detail'] ?? 'Application failed (${res.statusCode})');
  }
}
