// Decides where a ZanCrew user should go next:
// - Not signed in → pop with error
// - No profile → Onboarding
// - Missing preferences → Onboarding
// - No UK application → UkWorkStatusScreen
// - UK pending → UkPendingScreen
// - UK rejected/suspended → UkRejectedScreen
// - UK approved + can_receive_offers → check active job → Dashboard
//
// lib/features/zancrew/gateway/zancrew_gateway.dart

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zanzo_frontend/core/services/api_service.dart';

import '../../../core/services/uk_provider_api.dart';
import '../../../core/services/zancrew_api.dart';
import '../dashboard/zancrew_dashboard.dart';
import '../onboarding/uk_pending_screen.dart';
import '../onboarding/uk_rejected_screen.dart';
import '../onboarding/uk_work_status_screen.dart';
import '../onboarding/zancrew_onboarding.dart';
import '../screens/zancrew_JobDetails.dart';

class ZanCrewGateway extends StatefulWidget {
  const ZanCrewGateway({super.key});

  @override
  State<ZanCrewGateway> createState() => _ZanCrewGatewayState();
}

class _ZanCrewGatewayState extends State<ZanCrewGateway> {
  @override
  void initState() {
    super.initState();
    _decideNext();
  }

  // ---------------------------------------------------------------------------
  // MAIN DECISION FLOW
  // ---------------------------------------------------------------------------
  Future<void> _decideNext() async {
    final prefs = await SharedPreferences.getInstance();

    // -------------------------------------------------------------------------
    // 1) Ensure user is signed in
    // -------------------------------------------------------------------------
    final phone = prefs.getString('user_phone');
    if (phone == null || phone.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please sign in first')));
      Navigator.pop(context);
      return;
    }

    // -------------------------------------------------------------------------
    // 2) Ensure user ID exists
    // -------------------------------------------------------------------------
    final userId = prefs.getString('user_id');
    if (userId == null || userId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User error: No user_id found')),
      );
      Navigator.pop(context);
      return;
    }

    // -------------------------------------------------------------------------
    // 3) Fetch ZanCrew profile from backend
    // -------------------------------------------------------------------------
    try {
      final profile = await ZanCrewApi.getProfile(userId);

      // No profile → start onboarding
      if (profile == null) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ZanCrewOnboarding()),
        );
        return;
      }

      // -----------------------------------------------------------------------
      // 4) Extract fields
      // -----------------------------------------------------------------------
      final buckets = (profile['buckets'] as List?)?.cast<String>() ?? [];

      // -----------------------------------------------------------------------
      // CASE A — Preferences missing → onboarding
      // -----------------------------------------------------------------------
      if (buckets.isEmpty) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ZanCrewOnboarding()),
        );
        return;
      }

      // -----------------------------------------------------------------------
      // CASE B — UK provider status gate (replaces India KYC gate)
      // -----------------------------------------------------------------------
      final ukStatus = await UkProviderApi.getStatus(userId);

      if (!mounted) return;

      if (ukStatus == null) {
        // No application submitted yet → work status selection
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const UkWorkStatusScreen()),
        );
        return;
      }

      final providerStatus = ukStatus['provider_status'] as String? ?? 'pending';
      final canReceive = ukStatus['can_receive_offers'] == true;

      if (providerStatus == 'pending') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const UkPendingScreen()),
        );
        return;
      }

      if (providerStatus == 'rejected' || providerStatus == 'suspended') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => UkRejectedScreen(
              status: providerStatus,
              reason: ukStatus['rejection_reason'] as String?,
            ),
          ),
        );
        return;
      }

      if (providerStatus != 'approved' || !canReceive) {
        // Unexpected state — treat as pending
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const UkPendingScreen()),
        );
        return;
      }

      // -----------------------------------------------------------------------
      // CASE D — Check if this crew has an ACTIVE JOB
      // -----------------------------------------------------------------------
      try {
        final activeRes = await ApiService.getJson(
          '/zancrew/active_job?user_id=$userId',
        );

        if (activeRes.statusCode == 200) {
          final decoded = jsonDecode(activeRes.body);

          if (decoded is Map &&
              decoded['active'] == true &&
              decoded['job_id'] != null) {
            final jobId = decoded['job_id'].toString();
            if (!mounted) return;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => CrewJobDetail(jobId: jobId)),
            );
            return;
          }
        }
      } catch (_) {
        // ignore error → fall through to dashboard
      }

      // -----------------------------------------------------------------------
      // CASE C — Approved + can receive offers → dashboard
      // -----------------------------------------------------------------------
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const ZanCrewDashboard()),
      );
      return;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error loading profile: $e')));
      Navigator.pop(context);
    }
  }

  // ---------------------------------------------------------------------------
  // LOADING UI WHILE DECISION IS RUNNING
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}
