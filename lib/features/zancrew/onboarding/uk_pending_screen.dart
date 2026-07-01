// lib/features/zancrew/onboarding/uk_pending_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/uk_provider_api.dart';
import '../dashboard/zancrew_dashboard.dart';
import 'uk_rejected_screen.dart';

class UkPendingScreen extends StatefulWidget {
  const UkPendingScreen({super.key});

  @override
  State<UkPendingScreen> createState() => _UkPendingScreenState();
}

class _UkPendingScreenState extends State<UkPendingScreen> {
  static const _bg = Color(0xFFFCFAF6);
  static const _ink = Color(0xFF26211C);
  static const _muted = Color(0xFF9B8B7E);
  static const _accent = Color(0xFFD97706);

  Timer? _pollTimer;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    // Poll every 30 seconds while the screen is open
    _pollTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _checkStatus(),
    );
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    if (_checking) return;
    setState(() => _checking = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      if (userId == null || !mounted) return;

      final result = await UkProviderApi.getStatus(userId);
      if (result == null || !mounted) return;

      final providerStatus = result['provider_status'] as String? ?? 'pending';
      final canReceive = result['can_receive_offers'] == true;

      if (providerStatus == 'approved' && canReceive) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ZanCrewDashboard()),
        );
      } else if (providerStatus == 'rejected' ||
          providerStatus == 'suspended') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => UkRejectedScreen(
              status: providerStatus,
              reason: result['rejection_reason'] as String?,
            ),
          ),
        );
      }
    } catch (_) {
      // ignore transient poll errors
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text(
          'Application Pending',
          style: TextStyle(
            color: _ink,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
        backgroundColor: _bg,
        foregroundColor: _ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: const BoxDecoration(
                  color: Color(0xFFFEF3C7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.hourglass_top_outlined,
                  size: 40,
                  color: _accent,
                ),
              ),
              const SizedBox(height: 28),
              const Text(
                'Application under review',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                  letterSpacing: -0.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Your application has been submitted and is being reviewed by our team.\n\nThis usually takes 1–2 working days. You will be able to receive job offers once approved.',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey.shade700,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 44),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _checking ? null : _checkStatus,
                  icon: _checking
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.refresh, size: 20),
                  label: const Text(
                    'Check Status',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15.5,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    disabledBackgroundColor: const Color(0xFFE8E2D9),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
                child: const Text(
                  'Back to Home',
                  style: TextStyle(color: _muted, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
