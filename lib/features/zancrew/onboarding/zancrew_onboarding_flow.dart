// -----------------------------------------------------------------------------
// ZanCrew Onboarding — FLOW ROUTER
//
// Purpose of this widget:
//  1) Determine **which onboarding screen** the user should see next
//  2) Fetch user's latest ZanCrew state from backend
//  3) Handle missing login → show OTP login prompt
//  4) Redirect to:
//       - Welcome screen (new user, no profile yet)
//       - Phone verification step
//       - Preferences step
//       - KYC step
//       - Dashboard (onboarding completed)
//
// How this file works:
//   • init() → load user_id → fetch /zancrew/state
//   • state.exits == false → send user to welcome onboarding
//   • state.onboarding_step determines the next screen:
//          "phone"  → phone flow
//          "prefs"  → preferences
//          "kyc"    → KYC intro
//          "done"   → dashboard
//
// File: lib/features/zancrew/onboarding/zancrew_onboarding_flow.dart
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/zancrew_api.dart';
import '../../user/widgets/login_prompt_dialog.dart';
import '../dashboard/zancrew_dashboard.dart';
import '../gateway/zancrew_gateway.dart';
import 'zancrew_onboarding.dart'; // placeholder onboarding screen

class ZanCrewOnboardingFlow extends StatefulWidget {
  const ZanCrewOnboardingFlow({super.key});

  @override
  State<ZanCrewOnboardingFlow> createState() => _ZanCrewOnboardingFlowState();
}

class _ZanCrewOnboardingFlowState extends State<ZanCrewOnboardingFlow> {
  bool _loading = true;
  String? _userId;
  Map<String, dynamic>? _state;

  @override
  void initState() {
    super.initState();
    _init();
  }

  // ---------------------------------------------------------------------------
  // Load user ID → then load ZanCrew state from backend
  // ---------------------------------------------------------------------------
  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('user_id');

    // If user is not logged in → show OTP login popup
    if (uid == null) {
      final ok = await showLoginPrompt(context);
      if (!ok || !mounted) return Navigator.pop(context);
      return _init(); // retry after login
    }

    try {
      final state = await ZanCrewApi.getState(uid);

      if (!mounted) return;
      setState(() {
        _userId = uid;
        _state = state;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error loading ZanCrew state: $e")),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_userId == null) {
      return const Scaffold(
        body: Center(child: Text("Missing user ID")),
      );
    }

    return _decideNext();
  }

  // ---------------------------------------------------------------------------
  // MAIN ROUTING LOGIC
  // ---------------------------------------------------------------------------
  Widget _decideNext() {
    final exists = _state?['exists'] == true;
    final step = _state?['onboarding_step'] ?? 'welcome';

    // If no ZanCrew profile exists → send user into gateway/welcome flow
    if (!exists) {
      return const ZanCrewGateway();
    }

    // If profile exists, route based on step
    switch (step) {
      case 'phone':
        return const ZanCrewOnboarding();
      case 'prefs':
        return const ZanCrewOnboarding();
      case 'kyc':
        return const ZanCrewOnboarding();
      case 'done':
        return const ZanCrewDashboard();
    }

    // Fallback
    return const ZanCrewGateway();
  }
}