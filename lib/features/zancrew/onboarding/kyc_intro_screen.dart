// -----------------------------------------------------------------------------
// ZanCrew Onboarding — PHONE CHECK SCREEN
//
// Purpose:
//  1) Detect if user's phone is already verified (from SharedPreferences)
//  2) If verified → jump to ConfirmPhoneScreen
//  3) If not verified → open OTP login dialog (showLoginPrompt)
//  4) After OTP success → go to Preferences setup
//  5) If user cancels → exit onboarding (pop)
//
// File: lib/features/zancrew/onboarding/phone_check_screen.dart
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zanzo_frontend/core/services/zancrew_api.dart';

import '../dashboard/zancrew_dashboard.dart';
import '../screens/zancrew_verification.dart';

class KycIntroScreen extends StatefulWidget {
  final String? userId;
  const KycIntroScreen({super.key, this.userId});

  @override
  State<KycIntroScreen> createState() => _KycIntroScreenState();
}

class _KycIntroScreenState extends State<KycIntroScreen> {
  // ---------------------------------------------------------------------------
  // COLORS (Brand constants)
  // ---------------------------------------------------------------------------
  static const _brand = Color(0xFF5B3DF0);
  static const _accent = Color(0xFF00C389);
  static const _ink = Color(0xFF0F172A);

  bool _loading = true;
  String? _userId;

  // Server-side verification flags
  bool _panOk = false;
  bool _bankOk = false;
  bool _aadhaarOk = false;
  bool _selfieOk = false;

  String _status = 'pending'; // server status: pending / active / rejected...

  bool get _allVerified => _panOk && _bankOk && _aadhaarOk && _selfieOk;

  // ---------------------------------------------------------------------------
  // 1) INITIALIZE → Resolve user ID → Fetch verification state
  // ---------------------------------------------------------------------------
  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final uid = await _resolveUserId();
    setState(() => _userId = uid);
    await _refresh();
  }

  // Resolve userId: from constructor → fallback: SharedPreferences
  Future<String?> _resolveUserId() async {
    if (widget.userId != null && widget.userId!.isNotEmpty) {
      return widget.userId;
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id');
  }

  // ---------------------------------------------------------------------------
  // 2) REFRESH FROM SERVER → Get PAN + Bank + Aadhaar + Selfie status
  // ---------------------------------------------------------------------------
  Future<void> _refresh() async {
    if (_userId == null) {
      setState(() {
        _loading = false;
        _status = 'no_user';
      });
      return;
    }

    setState(() => _loading = true);

    try {
      final profile = await ZanCrewApi.getProfile(_userId!);
      if (!mounted) return;

      if (profile != null) {
        setState(() {
          _status = (profile['status'] as String?) ?? 'pending';

          _panOk = (profile['kyc_verified'] as bool?) ?? false;
          _bankOk = (profile['bank_verified'] as bool?) ?? false;
          _aadhaarOk = (profile['aadhaar_verified'] as bool?) ?? false;
          _selfieOk = (profile['liveness_verified'] as bool?) ?? false;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // 3) BEGIN VERIFICATION FLOW
  //    Navigate → ZanCrewVerification → Return → Re-check status
  // ---------------------------------------------------------------------------
  Future<void> _beginVerification() async {
    if (_userId == null) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ZanCrewVerification(userId: _userId!),
      ),
    );

    await _refresh(); // After returning, update progress

    if (_allVerified) {
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ZanCrewDashboard()),
        (_) => false,
      );
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Verification incomplete. Please finish all steps.'),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // 4) UI
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final verifiedCount = [
      _panOk,
      _bankOk,
      _aadhaarOk,
      _selfieOk,
    ].where((v) => v).length;

    final progress = verifiedCount / 4.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FB),
      appBar: AppBar(
        title: const Text('Become a ZanCrew Member'),
        backgroundColor: _brand,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (_userId == null)
              ? _missingUser()
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                  children: [
                    _heroCard(),
                    const SizedBox(height: 14),
                    _progressCard(progress, verifiedCount),
                    const SizedBox(height: 14),
                    _bulletCard(),
                    const SizedBox(height: 18),
                    _ctaButton(
                      label: _allVerified
                          ? 'Continue to Dashboard'
                          : 'Begin Verification',
                      onPressed:
                          _allVerified ? _goDashboard : _beginVerification,
                    ),
                    _statusFooter(),
                    _refreshButton(),
                  ],
                ),
    );
  }

  // ---------------------------------------------------------------------------
  // 4A) Missing user state
  // ---------------------------------------------------------------------------
  Widget _missingUser() {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_outline, size: 48, color: Colors.black45),
            SizedBox(height: 10),
            Text(
              'Please sign in first to continue.',
              style: TextStyle(fontSize: 16, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 4B) Hero illustration card (top banner)
  // ---------------------------------------------------------------------------
  Widget _heroCard() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5B3DF0), Color(0xFF8C6CFF)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Row(
        children: [
          // Small vector-style illustration
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned(
                  top: 16,
                  child: Icon(
                    Icons.badge_rounded,
                    size: 44,
                    color: Colors.white.withOpacity(0.95),
                  ),
                ),
                Positioned(
                  bottom: 12,
                  right: 12,
                  child: Icon(
                    Icons.verified,
                    size: 26,
                    color: Colors.white.withOpacity(0.95),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'Get verified to start earning with ZanCrew.',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                height: 1.25,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 4C) Progress card (0% → 100%)
  // ---------------------------------------------------------------------------
  Widget _progressCard(double progress, int verifiedCount) {
    final pct = (progress * 100).round();

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Verification Progress',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: _ink,
              ),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: Colors.grey.shade200,
                valueColor: const AlwaysStoppedAnimation(Color(0xFF00C389)),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$verifiedCount of 4 complete  ·  $pct%',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 4D) Checklist card (PAN / Bank / Aadhaar / Selfie)
  // ---------------------------------------------------------------------------
  Widget _bulletCard() {
    Widget bullet(bool done, String title, String hint) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            done ? Icons.check_circle : Icons.radio_button_unchecked,
            color: done ? _accent : Colors.grey,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(
                    color: _ink,
                    height: 1.25,
                    fontSize: 14,
                  ),
                  children: [
                    TextSpan(
                      text: '$title  ',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    TextSpan(text: hint),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'What you’ll complete',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: _ink,
              ),
            ),
            const SizedBox(height: 10),

            bullet(_panOk, 'PAN card', 'Name + DOB validation'),
            bullet(_bankOk, 'Bank account', 'Account & IFSC check'),
            bullet(_aadhaarOk, 'Aadhaar OCR',
                'Front & back scan (server verified after payment)'),
            bullet(_selfieOk, 'Selfie with liveness',
                'Face match & liveness (server verified after payment)'),

            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7E8),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                'We start verification only after payment is confirmed via webhook. '
                'Results update automatically — no manual refresh needed.',
                style: TextStyle(fontSize: 12, color: Colors.black87),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 4E) CTA Button
  // ---------------------------------------------------------------------------
  Widget _ctaButton({
    required String label,
    required VoidCallback? onPressed,
  }) {
    return SizedBox(
      height: 54,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: EdgeInsets.zero,
          backgroundColor: Colors.transparent,
        ),
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: onPressed == null
                  ? [Colors.grey.shade300, Colors.grey.shade400]
                  : const [Color(0xFF5B3DF0), Color(0xFF7C62FF)],
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Container(
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                color: onPressed == null ? Colors.black45 : Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Helper: Go to dashboard
  // ---------------------------------------------------------------------------
  void _goDashboard() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ZanCrewDashboard()),
      (_) => false,
    );
  }

  // Footer: Show status text
  Widget _statusFooter() {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Center(
        child: Text(
          'Status: ${_status.toUpperCase()}',
          style: const TextStyle(
            fontSize: 12,
            color: Colors.black54,
          ),
        ),
      ),
    );
  }

  // Footer: Refresh status
  Widget _refreshButton() {
    return Center(
      child: TextButton.icon(
        onPressed: _refresh,
        icon: const Icon(Icons.refresh),
        label: const Text('Refresh status'),
      ),
    );
  }
}