// Decides where a ZanCrew user should go next:
// - Not signed in → pop with error
// - No profile → Onboarding
// - Missing preferences → Onboarding
// - India user (country_code IN / +91) → Dashboard directly (skips UK forms)
// - No UK application → UkWorkStatusScreen
// - UK pending → UkPendingScreen
// - UK rejected/suspended → UkRejectedScreen
// - UK approved + can_receive_offers → Dashboard
//
// lib/features/zancrew/gateway/zancrew_gateway.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/uk_provider_api.dart';
import '../../../core/services/zancrew_api.dart';
import '../../../core/widgets/error_state.dart';
import '../../../core/widgets/skeleton.dart';
import '../dashboard/zancrew_dashboard.dart';
import '../onboarding/uk_pending_screen.dart';
import '../onboarding/uk_rejected_screen.dart';
import '../onboarding/uk_work_status_screen.dart';
import '../onboarding/zancrew_onboarding.dart';

class ZanCrewGateway extends StatefulWidget {
  const ZanCrewGateway({super.key});

  @override
  State<ZanCrewGateway> createState() => _ZanCrewGatewayState();
}

class _ZanCrewGatewayState extends State<ZanCrewGateway> {
  bool _error = false;

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

    // India users don't go through the UK right-to-work provider flow — they
    // skip the UK application/status forms and land straight on the dashboard.
    final countryCode = prefs.getString('country_code');
    final isIndia = countryCode == 'IN' || phone.startsWith('+91');

    // -------------------------------------------------------------------------
    // 3) Fetch ZanCrew profile from backend
    // -------------------------------------------------------------------------
    // Kick off BOTH calls immediately so they overlap on the wire. The profile
    // decides the early branches; the UK status is only needed on the "has
    // buckets" path (UK users only), where it's already in flight by the time
    // we await it — halving the network wait on the common approved→dashboard
    // route. The catchError keeps an ignored rejection (early-return branches)
    // from surfacing as an unhandled async error. India users never need it.
    final ukStatusFuture = isIndia
        ? null
        : UkProviderApi.getStatus(userId).catchError((_) => null);
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
      final bucketsRaw = profile['buckets'];
      final hasBuckets =
          (bucketsRaw is String && bucketsRaw.trim().isNotEmpty) ||
          (bucketsRaw is List && bucketsRaw.isNotEmpty);

      // -----------------------------------------------------------------------
      // CASE A — Preferences missing → onboarding
      // -----------------------------------------------------------------------
      if (!hasBuckets) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ZanCrewOnboarding()),
        );
        return;
      }

      // -----------------------------------------------------------------------
      // INDIA — skip the UK provider application/status gate entirely and go
      // straight to the dashboard so the user can see tasks directly.
      // -----------------------------------------------------------------------
      if (isIndia) {
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ZanCrewDashboard()),
        );
        return;
      }

      // -----------------------------------------------------------------------
      // CASE B — UK provider status gate (replaces India KYC gate)
      // -----------------------------------------------------------------------
      // Non-null here: only UK users reach this gate (India returned above).
      final ukStatus = await ukStatusFuture!;

      if (!mounted) return;

      if (ukStatus == null) {
        // No application submitted yet → work status selection
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const UkWorkStatusScreen()),
        );
        return;
      }

      final providerStatus =
          ukStatus['provider_status'] as String? ?? 'pending';
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
      // Inline error state with retry instead of a snackbar + pop.
      setState(() => _error = true);
    }
  }

  // ---------------------------------------------------------------------------
  // LOADING UI WHILE DECISION IS RUNNING
  // ---------------------------------------------------------------------------
  // Mirror the dashboard chrome — header (back, title, icons) + the two tabs +
  // offer-shaped shimmer — so tapping Work never flashes a headerless full-
  // screen shimmer before the dashboard (the common destination) mounts.
  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFFFCFAF6);
    const ink = Color(0xFF26211C);
    const accent = Color(0xFFD97706);
    const muted = Color(0xFF8C8378);

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: bg,
          foregroundColor: ink,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          title: const Text(
            'ZanCrew',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.2),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.account_balance_outlined),
              onPressed: () {},
            ),
            IconButton(icon: const Icon(Icons.tune), onPressed: () {}),
          ],
          bottom: const TabBar(
            labelColor: ink,
            unselectedLabelColor: muted,
            indicatorColor: accent,
            indicatorWeight: 3,
            labelStyle: TextStyle(fontWeight: FontWeight.w900),
            tabs: [
              Tab(text: 'Offers'),
              Tab(text: 'Active'),
            ],
          ),
        ),
        body: _error
            ? ErrorState(
                message: "We couldn't open ZanCrew. Please try again.",
                onRetry: () {
                  setState(() => _error = false);
                  _decideNext();
                },
              )
            : const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: SkeletonOfferList(
                  padding: EdgeInsets.fromLTRB(0, 4, 0, 16),
                ),
              ),
      ),
    );
  }
}
