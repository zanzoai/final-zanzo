// lib/features/zancrew/onboarding/uk_rejected_screen.dart
import 'package:flutter/material.dart';

import 'zancrew_onboarding.dart';

class UkRejectedScreen extends StatelessWidget {
  final String status; // 'rejected' or 'suspended'
  final String? reason;

  const UkRejectedScreen({super.key, required this.status, this.reason});

  static const _bg = Color(0xFFFCFAF6);
  static const _ink = Color(0xFF26211C);
  static const _muted = Color(0xFF9B8B7E);
  static const _accent = Color(0xFFD97706);
  static const _border = Color(0xFFE8E2D9);

  @override
  Widget build(BuildContext context) {
    final isSuspended = status == 'suspended';

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: Text(
          isSuspended ? 'Account Suspended' : 'Application Update Needed',
          style: const TextStyle(
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
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 32),

              // Status icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: isSuspended
                      ? const Color(0xFFFEE2E2)
                      : const Color(0xFFFEF3C7),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isSuspended
                      ? Icons.pause_circle_outline
                      : Icons.edit_note_outlined,
                  size: 40,
                  color: isSuspended ? const Color(0xFFDC2626) : _accent,
                ),
              ),
              const SizedBox(height: 24),

              Text(
                isSuspended
                    ? 'Provider Access Suspended'
                    : 'Application needs updates',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                  letterSpacing: -0.3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),

              Text(
                isSuspended
                    ? 'Your provider access has been suspended. Please contact support if you think this is an error.'
                    : 'We reviewed your ZanCrew application and need a few updates before it can be approved.',
                style: const TextStyle(
                  fontSize: 15,
                  color: _muted,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),

              // Reason / feedback box
              if (reason != null && reason!.isNotEmpty) ...[
                const SizedBox(height: 24),
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
                            decoration: BoxDecoration(
                              color: isSuspended
                                  ? const Color(0xFFDC2626)
                                  : _accent,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Feedback from our team',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isSuspended
                                  ? const Color(0xFFDC2626)
                                  : _accent,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        reason!,
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

              const SizedBox(height: 44),

              // Update and reapply (rejected only)
              if (!isSuspended) ...[
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ZanCrewOnboarding(),
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
                      'Update and reapply',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Back to home
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  onPressed: () =>
                      Navigator.popUntil(context, (r) => r.isFirst),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _ink,
                    side: const BorderSide(color: _border, width: 1.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Back to Home',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
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
