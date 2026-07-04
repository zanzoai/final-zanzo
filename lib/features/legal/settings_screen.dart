// lib/features/legal/settings_screen.dart

import 'package:flutter/material.dart';

const _kBg = Color(0xFFFCFAF6);
const _kInk = Color(0xFF26211C);
const _kMuted = Color(0xFF8C8378);
const _kLine = Color(0xFFE8E2D9);
const _kSaffron = Color(0xFFD97706);

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const routeName = '/settings';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        title: const Text(
          'Legal & Safety',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: _kBg,
        foregroundColor: _kInk,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 10),
              child: Text(
                'LEGAL & SAFETY',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _kMuted,
                  letterSpacing: 0.8,
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _kLine),
              ),
              child: const Column(
                children: [
                  _SettingsRow(
                    icon: Icons.description_outlined,
                    title: 'Terms & Conditions',
                    subtitle: 'How Zanzo works and your responsibilities',
                    route: '/terms',
                    showDivider: true,
                  ),
                  _SettingsRow(
                    icon: Icons.privacy_tip_outlined,
                    title: 'Privacy Policy',
                    subtitle: 'What data we collect and how we use it',
                    route: '/privacy',
                    showDivider: true,
                  ),
                  _SettingsRow(
                    icon: Icons.assignment_outlined,
                    title: 'Task Rules & Safety',
                    subtitle: 'What tasks are allowed and what to avoid',
                    route: '/task_rules',
                    showDivider: false,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.route,
    required this.showDivider,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String route;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => Navigator.pushNamed(context, route),
            borderRadius: BorderRadius.vertical(
              top: showDivider
                  ? const Radius.circular(0)
                  : const Radius.circular(0),
              bottom: showDivider
                  ? const Radius.circular(0)
                  : const Radius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 19, color: _kSaffron),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _kInk,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 12,
                            color: _kMuted,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right, color: _kMuted, size: 20),
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          const Divider(height: 1, color: _kLine, indent: 68, endIndent: 0),
      ],
    );
  }
}
