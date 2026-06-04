// lib/core/services/auth.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zanzo_frontend/core/services/api_service.dart';
import 'package:zanzo_frontend/features/user/screens/profile_screen.dart';
import 'package:zanzo_frontend/features/user/widgets/login_prompt_dialog.dart';

class Auth {
  /// Check if user is signed in (phone-based).
  static Future<bool> isSignedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id') != null &&
        prefs.getString('user_phone') != null;
  }

  /// Get current user ID
  static Future<String?> userId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id');
  }

  /// Sign out — invalidates the refresh token on the server then clears all local data.
  static Future<void> signOut() async {
    await ApiService.logout();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  /// If not signed in → show OTP login modal.
  /// Returns true when login is completed.
  static Future<bool> requireSignIn(BuildContext context) async {
    if (await isSignedIn()) return true;

    final ok = await showLoginPrompt(context);

    if (ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("✅ You're signed in")),
      );
    }

    return ok;
  }

  /// Open Profile screen only if user is signed in.
  static Future<void> openProfile(BuildContext context) async {
    final ok = await requireSignIn(context);
    if (!ok || !context.mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
  }
}