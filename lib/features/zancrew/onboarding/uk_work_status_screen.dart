// lib/features/zancrew/onboarding/uk_work_status_screen.dart
import 'package:flutter/material.dart';

import 'uk_apply_screen.dart';

class UkWorkStatusScreen extends StatelessWidget {
  const UkWorkStatusScreen({super.key});

  static const _bg = Color(0xFFFCFAF6);
  static const _ink = Color(0xFF26211C);
  static const _muted = Color(0xFF9B8B7E);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text(
          'Right to Work',
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
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          children: [
            const Text(
              'Your work status',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: _ink,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'We review work status before activating paid tasks on Zanzo.',
              style: TextStyle(fontSize: 14, color: _muted, height: 1.4),
            ),
            const SizedBox(height: 20),
            const _StatusTile(
              title: 'British / Irish citizen',
              subtitle: 'UK or Irish passport holder',
              value: 'british_irish',
              requiresShareCode: false,
              icon: Icons.person_outline,
            ),
            const _StatusTile(
              title: 'EU Settled or Pre-Settled Status',
              subtitle: 'EUSS granted — we may ask for a GOV.UK share code',
              value: 'settled_pre_settled',
              requiresShareCode: true,
              icon: Icons.public_outlined,
            ),
            const _StatusTile(
              title: 'Graduate Visa',
              subtitle:
                  'Post-study work permission — we may ask for a GOV.UK share code',
              value: 'graduate_visa',
              requiresShareCode: true,
              icon: Icons.school_outlined,
            ),
            const _StatusTile(
              title: 'Skilled Worker / restricted work visa',
              subtitle:
                  'Share your details so our team can review your work permission',
              value: 'skilled_worker_or_other',
              requiresShareCode: true,
              icon: Icons.work_outline,
            ),
            const _StatusTile(
              title: 'Student Visa',
              subtitle: "We'll collect a few extra details for review.",
              value: 'student_visa',
              requiresShareCode: true,
              icon: Icons.menu_book_outlined,
            ),
            const _StatusTile(
              title: "Other visa / I'm not sure",
              subtitle:
                  'Choose this if you need help confirming your work status.',
              value: 'unknown',
              requiresShareCode: false,
              icon: Icons.help_outline,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String value;
  final bool requiresShareCode;
  final IconData icon;

  const _StatusTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.requiresShareCode,
    required this.icon,
  });

  static const _ink = Color(0xFF26211C);
  static const _muted = Color(0xFF9B8B7E);
  static const _accent = Color(0xFFD97706);
  static const _border = Color(0xFFE8E2D9);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => UkApplyScreen(
                workStatus: value,
                requiresShareCode: requiresShareCode,
              ),
            ),
          ),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _border),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x07000000),
                  blurRadius: 10,
                  offset: Offset(0, 3),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            child: Row(
              children: [
                // Icon badge
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(icon, size: 20, color: _accent),
                ),
                const SizedBox(width: 14),
                // Text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: _muted,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right, color: _accent, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
