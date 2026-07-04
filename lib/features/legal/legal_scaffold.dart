// lib/features/legal/legal_scaffold.dart
// Shared scaffold and section card widgets for legal/trust pages.

import 'package:flutter/material.dart';

const _kBg = Color(0xFFFCFAF6);
const _kInk = Color(0xFF26211C);
const _kMuted = Color(0xFF8C8378);
const _kLine = Color(0xFFE8E2D9);
const _kSaffron = Color(0xFFD97706);

class LegalScaffold extends StatelessWidget {
  const LegalScaffold({
    super.key,
    required this.title,
    required this.sections,
    this.lastUpdated,
  });

  final String title;
  final List<Widget> sections;
  final String? lastUpdated;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: _kBg,
        foregroundColor: _kInk,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...sections,
              if (lastUpdated != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Last updated: $lastUpdated',
                  style: const TextStyle(fontSize: 12, color: _kMuted),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class LegalSection extends StatelessWidget {
  const LegalSection({
    super.key,
    required this.title,
    required this.child,
    this.icon,
  });

  final String title;
  final Widget child;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _kLine),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 16, color: _kSaffron),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _kInk,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class LegalBullet extends StatelessWidget {
  const LegalBullet(this.text, {super.key, this.strong = false});

  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '•  ',
            style: TextStyle(
              fontSize: 13.5,
              color: strong ? _kInk : _kMuted,
              height: 1.55,
              fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13.5,
                color: strong ? _kInk : _kMuted,
                height: 1.55,
                fontWeight: strong ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const legalBodyStyle = TextStyle(
  fontSize: 13.5,
  color: _kMuted,
  height: 1.6,
  fontWeight: FontWeight.w400,
);
