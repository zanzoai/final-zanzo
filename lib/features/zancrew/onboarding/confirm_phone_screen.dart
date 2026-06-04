// -----------------------------------------------------------------------------
// ZanCrew Onboarding — CONFIRM PHONE SCREEN
//
// This screen appears when the user already has a verified phone number stored.
// Purpose:
//  1) Load saved phone number from SharedPreferences
//  2) Ask user whether to use the same phone for ZanCrew
//  3) Allow user to restart phone verification if they want to change it
//
// Navigation:
//   Use same number  →  ZanCrewPreferencesScreen
//   Change number    →  ZanCrewPhoneCheckScreen
//
// File: lib/features/zancrew/onboarding/confirm_phone_screen.dart
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'phone_check_screen.dart';
import 'preferences_screen.dart';

class ConfirmPhoneScreen extends StatefulWidget {
  const ConfirmPhoneScreen({super.key});

  @override
  State<ConfirmPhoneScreen> createState() => _ConfirmPhoneScreenState();
}

class _ConfirmPhoneScreenState extends State<ConfirmPhoneScreen> {
  String? _phone;

  // ---------------------------------------------------------------------------
  // 1) LOAD SAVED PHONE NUMBER (SharedPreferences)
  // ---------------------------------------------------------------------------
  @override
  void initState() {
    super.initState();
    _loadPhone();
  }

  Future<void> _loadPhone() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _phone = prefs.getString('user_phone') ?? '';
    });
  }

  // ---------------------------------------------------------------------------
  // 2) USE SAME NUMBER → Move to Preferences screen
  // ---------------------------------------------------------------------------
  Future<void> _useSameNumber() async {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const ZanCrewPreferencesScreen()),
    );
  }

  // ---------------------------------------------------------------------------
  // 3) CHANGE NUMBER → Restart phone verification flow
  // ---------------------------------------------------------------------------
  Future<void> _changeNumber() async {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const ZanCrewPhoneCheckScreen()),
    );
  }

  // ---------------------------------------------------------------------------
  // 4) UI
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final phone = _phone ?? "";

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 40),

              const Text(
                "Confirm your phone",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 16),

              Text(
                "We found $phone already verified.\nDo you want to use this number for ZanCrew?",
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.black54,
                  height: 1.4,
                ),
              ),

              const Spacer(),

              // --- Confirm Button ---
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _useSameNumber,
                  child: const Text(
                    "Use this number",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // --- Change Number Button ---
              TextButton(
                onPressed: _changeNumber,
                child: const Text(
                  "Change number",
                  style: TextStyle(color: Colors.red, fontSize: 15),
                ),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}