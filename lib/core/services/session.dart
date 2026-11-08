// lib/core/services/session.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zanzo_frontend/core/live_activity/deep_link_service.dart';
import 'package:zanzo_frontend/core/services/token_store.dart';
import 'package:zanzo_frontend/core/utils/log.dart';

/// Ends the local session when the server says it is no longer valid (the
/// refresh token was rejected: expired, revoked, or the account was disabled).
class Session {
  Session._();

  static bool _expiring = false;

  /// Keys that only make sense while signed in. App-wide preferences such as
  /// onboarding flags are kept.
  static const _signedInKeys = [
    'user_id',
    'user_phone',
    'phone_verified',
    'user_role',
    'region',
    'country_code',
    'profile_photo_url',
  ];

  static Future<void> expire() async {
    if (_expiring) return; // several requests can fail at once; act once
    _expiring = true;
    try {
      dlog('[Session] refresh token rejected — signing out');
      await TokenStore.clear();
      final prefs = await SharedPreferences.getInstance();
      for (final k in _signedInKeys) {
        await prefs.remove(k);
      }
      final nav = DeepLinkService.navigatorKey.currentState;
      final ctx = DeepLinkService.navigatorKey.currentContext;
      if (nav != null) nav.popUntil((route) => route.isFirst);
      if (ctx != null && ctx.mounted) {
        ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(
          const SnackBar(
            content: Text('Your session has expired. Please sign in again.'),
          ),
        );
      }
    } finally {
      _expiring = false;
    }
  }
}
