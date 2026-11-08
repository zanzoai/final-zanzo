// lib/features/zancrew/onboarding/uk_resubmit_docs_screen.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/uk_provider_api.dart';
import '../dashboard/zancrew_dashboard.dart';
import 'uk_rejected_screen.dart';
import 'uk_work_status_screen.dart';

class UkResubmitDocsScreen extends StatefulWidget {
  final String? adminNotes;
  final String? rejectionReason;

  const UkResubmitDocsScreen({
    super.key,
    this.adminNotes,
    this.rejectionReason,
  });

  @override
  State<UkResubmitDocsScreen> createState() => _UkResubmitDocsScreenState();
}

class _UkResubmitDocsScreenState extends State<UkResubmitDocsScreen> {
  static const _bg = Color(0xFFFCFAF6);
  static const _ink = Color(0xFF26211C);
  static const _muted = Color(0xFF9B8B7E);
  static const _accent = Color(0xFFD97706);
  static const _border = Color(0xFFE8E2D9);

  Timer? _pollTimer;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
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

      final providerStatus = result['provider_status'] as String? ?? '';
      final canReceive = result['can_receive_offers'] == true;

      if (providerStatus == 'approved' && canReceive) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ZanCrewDashboard()),
        );
      } else if (providerStatus == 'rejected' || providerStatus == 'suspended') {
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
    final feedback = widget.adminNotes?.isNotEmpty == true
        ? widget.adminNotes
        : widget.rejectionReason?.isNotEmpty == true
        ? widget.rejectionReason
        : null;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text(
          'Action Required',
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),

              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: Color(0xFFFEF3C7),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.upload_file_outlined,
                  size: 36,
                  color: _accent,
                ),
              ),
              const SizedBox(height: 20),

              const Text(
                'Documents needed',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Our team has reviewed your application and needs updated documents before it can be approved.',
                style: TextStyle(fontSize: 15, color: _muted, height: 1.5),
              ),

              if (feedback != null) ...[
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: _accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Feedback from our team',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: _accent,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        feedback,
                        style: const TextStyle(
                          fontSize: 13.5,
                          color: _ink,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 36),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const UkWorkStatusScreen(),
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Resubmit Application',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _checking ? null : _checkStatus,
                  icon: _checking
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.refresh, size: 18),
                  label: const Text(
                    'Check Status',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE8E2D9),
                    foregroundColor: _ink,
                    elevation: 0,
                    disabledBackgroundColor: const Color(0xFFE8E2D9),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              Center(
                child: TextButton(
                  onPressed: () =>
                      Navigator.popUntil(context, (r) => r.isFirst),
                  child: const Text(
                    'Back to Home',
                    style: TextStyle(color: _muted, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
