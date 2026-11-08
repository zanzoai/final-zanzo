// lib/core/utils/log.dart
import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Debug-only logging. In release builds this does nothing, so request
/// bodies, OTP codes, tokens and personal data never reach the device log.
/// (`print` and `debugPrint` both still write to the system log in release.)
void dlog(Object? message) {
  if (kDebugMode) debugPrint('$message');
}

const _sensitiveKeys = {
  'code',
  'otp',
  'pin',
  'password',
  'current_password',
  'access_token',
  'refresh_token',
  'token',
  'client_secret',
  'customer_session_client_secret',
};

/// Copy of a JSON-like map with sensitive values masked, for debug logs.
Object? redact(Object? value) {
  if (value is Map) {
    return value.map(
      (k, v) => MapEntry(
        k,
        _sensitiveKeys.contains(k.toString().toLowerCase()) ? '***' : redact(v),
      ),
    );
  }
  if (value is List) return value.map(redact).toList();
  return value;
}

/// A JSON response body with sensitive values masked, for debug logs.
/// Non-JSON bodies are returned with any Stripe client secret masked.
String redactBody(String body) {
  try {
    return jsonEncode(redact(jsonDecode(body)));
  } catch (_) {
    return body.replaceAll(RegExp(r'_secret_[A-Za-z0-9]+'), '_secret_***');
  }
}
