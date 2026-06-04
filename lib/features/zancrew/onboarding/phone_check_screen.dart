// -----------------------------------------------------------------------------
// ZanCrew Onboarding — PHONE CHECK SCREEN
//
// Purpose:
//  1) Auto-detect if user's phone is already verified (from SharedPreferences)
//  2) If verified → go to ConfirmPhoneScreen
//  3) If not verified → open OTP login dialog (showLoginPrompt)
//  4) After successful OTP → go to Preferences screen
//  5) If user cancels → exit onboarding flow
//
// File: lib/features/zancrew/onboarding/phone_check_screen.dart
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zanzo_frontend/features/user/widgets/login_prompt_dialog.dart';

import 'confirm_phone_screen.dart';
import 'preferences_screen.dart';

class ZanCrewPhoneCheckScreen extends StatefulWidget {
  const ZanCrewPhoneCheckScreen({super.key});

  @override
  State<ZanCrewPhoneCheckScreen> createState() =>
      _ZanCrewPhoneCheckScreenState();
}

class _ZanCrewPhoneCheckScreenState extends State<ZanCrewPhoneCheckScreen> {
  @override
  void initState() {
    super.initState();
    _startCheck();
  }

  // ---------------------------------------------------------------------------
  // STEP 1: Auto-check phone state
  //
  // CASE A → Already verified → go to ConfirmPhoneScreen
  // CASE B → Not verified → show OTP popup (showLoginPrompt)
  // ---------------------------------------------------------------------------
  Future<void> _startCheck() async {
    await Future.delayed(const Duration(milliseconds: 150));

    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_phone');
    final phoneVerified = prefs.getBool('phone_verified') ?? false;

    // CASE A: Already verified
    if (phone != null && phone.isNotEmpty && phoneVerified) {
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ConfirmPhoneScreen()),
      );
      return;
    }

    // CASE B: Not verified → open OTP dialog
    if (!mounted) return;
    final ok = await showLoginPrompt(context);

    if (ok == true && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ZanCrewPreferencesScreen()),
      );
    } else {
      if (!mounted) return;
      Navigator.of(context).pop(); // cancelled onboarding
    }
  }

  // ---------------------------------------------------------------------------
  // LOADING SCREEN
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}