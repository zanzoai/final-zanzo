// lib/core/services/token_store.dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zanzo_frontend/core/utils/log.dart';

/// Holds the login tokens in the platform keystore (Android Keystore / iOS
/// Keychain) instead of plain SharedPreferences, where any backup or rooted
/// device could read them.
///
/// Tokens saved by older app versions in SharedPreferences are moved here the
/// first time they are read, then deleted from SharedPreferences.
class TokenStore {
  TokenStore._();

  static const _accessKey = 'access_token';
  static const _refreshKey = 'refresh_token';
  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static String? _access;
  static String? _refresh;
  static Future<void>? _loading;

  static Future<void> _load() => _loading ??= _doLoad();

  static Future<void> _doLoad() async {
    try {
      _access = await _storage.read(key: _accessKey);
      _refresh = await _storage.read(key: _refreshKey);
    } catch (e) {
      dlog('[TokenStore] secure read failed: $e');
    }
    // One-time migration from SharedPreferences (older app versions).
    final prefs = await SharedPreferences.getInstance();
    final legacyAccess = prefs.getString(_accessKey);
    final legacyRefresh = prefs.getString(_refreshKey);
    if (legacyAccess != null || legacyRefresh != null) {
      if (_access == null && legacyAccess != null && legacyAccess.isNotEmpty) {
        _access = legacyAccess;
        await _write(_accessKey, legacyAccess);
      }
      if (_refresh == null &&
          legacyRefresh != null &&
          legacyRefresh.isNotEmpty) {
        _refresh = legacyRefresh;
        await _write(_refreshKey, legacyRefresh);
      }
      await prefs.remove(_accessKey);
      await prefs.remove(_refreshKey);
    }
  }

  static Future<void> _write(String key, String? value) async {
    try {
      if (value == null || value.isEmpty) {
        await _storage.delete(key: key);
      } else {
        await _storage.write(key: key, value: value);
      }
    } catch (e) {
      dlog('[TokenStore] secure write failed: $e');
    }
  }

  static Future<String?> accessToken() async {
    await _load();
    return _access;
  }

  static Future<String?> refreshToken() async {
    await _load();
    return _refresh;
  }

  /// Save whichever tokens are given (null or empty values are ignored).
  static Future<void> save({String? access, String? refresh}) async {
    await _load();
    if (access != null && access.isNotEmpty) {
      _access = access;
      await _write(_accessKey, access);
    }
    if (refresh != null && refresh.isNotEmpty) {
      _refresh = refresh;
      await _write(_refreshKey, refresh);
    }
  }

  static Future<void> clear() async {
    await _load();
    _access = null;
    _refresh = null;
    await _write(_accessKey, null);
    await _write(_refreshKey, null);
  }
}
