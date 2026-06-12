// lib/zancrew_review.dart
// Clean-formatted version (B1: formatting only)

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/zancrew_api.dart';

class ZanCrewReview extends StatefulWidget {
  final String userId;
  const ZanCrewReview({super.key, required this.userId});

  @override
  State<ZanCrewReview> createState() => _ZanCrewReviewState();
}

class _ZanCrewReviewState extends State<ZanCrewReview> {
  bool _loading = true;
  Map<String, dynamic>? _profile;

  @override
  void initState() {
    super.initState();
    _load();
  }

  // ---------------------------------------------------------------------------
  // Mirror selected values from backend profile into SharedPreferences
  // ---------------------------------------------------------------------------
  Future<void> _mirrorToPrefs(Map<String, dynamic> p) async {
    final prefs = await SharedPreferences.getInstance();

    if (p['status'] is String) {
      await prefs.setString('zancrew_status', p['status'] as String);
      await prefs.setBool(
        'zancrew_enabled',
        (p['status'] as String) == 'active',
      );
    }

    if (p['bank_verified'] is bool) {
      await prefs.setBool('zancrew_bank_verified', p['bank_verified'] as bool);
    }

    if (p['kyc_verified'] is bool) {
      await prefs.setBool('zancrew_kyc_verified', p['kyc_verified'] as bool);
    }

    if (p['buckets'] is String) {
      final raw = p['buckets'] as String;
      if (raw.isNotEmpty) {
        await prefs.setStringList(
          'zancrew_buckets',
          raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
        );
      }
    } else if (p['buckets'] is List) {
      await prefs.setStringList(
        'zancrew_buckets',
        (p['buckets'] as List).cast<String>(),
      );
    }

    if (p['radius_km'] is num) {
      await prefs.setDouble(
        'zancrew_radius_km',
        (p['radius_km'] as num).toDouble(),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Load profile from server
  // ---------------------------------------------------------------------------
  Future<void> _load() async {
    setState(() => _loading = true);

    try {
      final profile = await ZanCrewApi.getProfile(widget.userId);
      if (!mounted) return;

      setState(() => _profile = profile);

      if (profile != null) {
        await _mirrorToPrefs(profile);
      }
    } catch (_) {
      // Ignore errors during MVP
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Activate → mark ACTIVE locally then best-effort update to backend
  // ---------------------------------------------------------------------------
  Future<void> _activateAndClose() async {
    final prefs = await SharedPreferences.getInstance();

    final buckets = prefs.getStringList('zancrew_buckets') ?? <String>[];
    final radiusKm = (prefs.getDouble('zancrew_radius_km') ?? 5.0).round();

    // Optimistic local activation
    await prefs.setString('zancrew_status', 'active');
    await prefs.setBool('zancrew_enabled', true);

    // Try updating backend
    try {
      await ZanCrewApi.upsertProfile(
        userId: widget.userId,
        buckets: buckets,
        radiusKm: radiusKm,
        status: 'active',
      );
    } catch (_) {
      // Ignore — local activation still allows flow
    }

    if (!mounted) return;
    Navigator.pop(context, true);
  }

    @override
  Widget build(BuildContext context) {
    final p = _profile ?? {};

    final status = (p['status'] as String? ?? 'pending').toLowerCase();
    final bucketsRaw = p['buckets'];
    final buckets = bucketsRaw is List
        ? List<String>.from(bucketsRaw)
        : bucketsRaw is String && bucketsRaw.isNotEmpty
            ? bucketsRaw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList()
            : const <String>[];
    final radiusKm = (p['radius_km'] as num?)?.toInt() ?? 0;
    final bankVerified = (p['bank_verified'] as bool?) ?? false;
    final kycVerified = (p['kyc_verified'] as bool?) ?? false;

    final checksDone = bankVerified && kycVerified;
    final allVerifiedAndActive = checksDone && status == 'active';

    final ctaEnabled = checksDone;
    final ctaText = allVerifiedAndActive
        ? 'Go to Dashboard'
        : (checksDone ? 'Activate & Continue' : 'Back to Verification');

    final ctaColor = checksDone ? Colors.green : Colors.orange;
    final ctaIcon = checksDone ? Icons.check_circle : Icons.arrow_back;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Review & Activate'),
        backgroundColor: Colors.orangeAccent,
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StatusHeader(status: status, checksDone: checksDone),
                  const SizedBox(height: 16),

                  // ------- Preferences summary -------
                  _SectionCard(
                    title: 'Your work preferences',
                    children: [
                      _RowItem(
                        label: 'Preferred Work Types',
                        value: buckets.isEmpty ? '—' : buckets.join(', '),
                        multiline: true,
                      ),
                      _RowItem(label: 'Radius', value: '$radiusKm km'),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // ------- Verification summary -------
                  _SectionCard(
                    title: 'Verification',
                    children: [
                      _VerifyRowInline(
                        checked: bankVerified,
                        label: 'Bank account',
                        hint: 'Masked later • IFSC shown',
                      ),
                      const SizedBox(height: 8),
                      _VerifyRowInline(
                        checked: kycVerified,
                        label: 'KYC (ID + selfie)',
                        hint: 'Aadhaar/PAN • Liveness',
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // ------- CTA button -------
                  Center(
                    child: ElevatedButton.icon(
                      onPressed: !ctaEnabled
                          ? () => Navigator.pop(context, false)
                          : () async {
                              if (status == 'active') {
                                Navigator.pop(context, true);
                              } else {
                                await _activateAndClose();
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: ctaColor,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                      ),
                      icon: Icon(ctaIcon),
                      label: Text(ctaText),
                    ),
                  ),

                  const SizedBox(height: 8),

                  if (!checksDone)
                    const Center(
                      child: Text(
                        'Complete both checks to activate your account.',
                        style: TextStyle(color: Colors.black54),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

// ===================================================================
// STATUS HEADER
// ===================================================================
class _StatusHeader extends StatelessWidget {
  final String status;
  final bool checksDone;

  const _StatusHeader({
    required this.status,
    required this.checksDone,
  });

  @override
  Widget build(BuildContext context) {
    final color = (status == 'active' && checksDone)
        ? Colors.green
        : (status == 'pending' ? Colors.orange : Colors.grey);

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            status.toUpperCase(),
            style: TextStyle(
              color: color[800],
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            'Review your details. Activate when ready.',
            style: TextStyle(color: Colors.black54),
          ),
        ),
      ],
    );
  }
}

// ===================================================================
// SECTION CARD
// ===================================================================
class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SectionCard({
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }
}

// ===================================================================
// ROW ITEM (Label : Value)
// ===================================================================
class _RowItem extends StatelessWidget {
  final String label;
  final String value;
  final bool multiline;

  const _RowItem({
    required this.label,
    required this.value,
    this.multiline = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment:
            multiline ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          // Label
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: const TextStyle(color: Colors.black54),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),

          // Value
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
              maxLines: multiline ? 6 : 1,
              overflow:
                  multiline ? TextOverflow.visible : TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ===================================================================
// INLINE VERIFY INDICATOR
// ===================================================================
class _VerifyRowInline extends StatelessWidget {
  final bool checked;
  final String label;
  final String hint;

  const _VerifyRowInline({
    required this.checked,
    required this.label,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    final icon = checked ? Icons.check_circle : Icons.radio_button_unchecked;
    final color = checked ? Colors.green : Colors.grey;

    return Row(
      children: [
        // Label
        SizedBox(
          width: 160,
          child: Text(
            label,
            style: const TextStyle(color: Colors.black54),
          ),
        ),

        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),

        // Verified / Not verified
        Expanded(
          child: Text(
            checked ? 'Verified' : 'Not verified',
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),

        // Hint
        Flexible(
          child: Text(
            hint,
            style: const TextStyle(color: Colors.black38, fontSize: 12),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }
}