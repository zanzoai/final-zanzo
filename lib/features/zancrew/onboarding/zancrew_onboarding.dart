// -----------------------------------------------------------------------------
// ZanCrew Onboarding — PREFERENCES SCREEN (First-time + Edit Mode)
//
// Purpose of this screen:
//   • Allow users to select categories (skills) they can do
//   • Allow users to set service radius
//   • Save preferences locally + backend
//   • First-time → status = "pending" → proceed to verification
//   • Edit mode → status remains "active" → update prefs with weekly edit limit
//
// When used:
//   • Fresh users after phone verification
//   • Returning earners editing their categories + radius
//
// File: lib/features/zancrew/onboarding/zancrew_onboarding.dart
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/zancrew_api.dart';
import 'uk_work_status_screen.dart';

class ZanCrewOnboarding extends StatefulWidget {
  /// If true → user is editing existing prefs instead of first-time setup.
  final bool editMode;
  const ZanCrewOnboarding({super.key, this.editMode = false});

  @override
  State<ZanCrewOnboarding> createState() => _ZanCrewOnboardingState();
}

class _ZanCrewOnboardingState extends State<ZanCrewOnboarding> {
  static const _bg = Color(0xFFFCFAF6);
  static const _ink = Color(0xFF26211C);
  static const _muted = Color(0xFF9B8B7E);
  static const _accent = Color(0xFFD97706);
  static const _border = Color(0xFFE8E2D9);

  static const List<String> _allBuckets = [
    'Delivery',
    'Cleaning',
    'Moving',
    'Errands',
    'Tech Help',
    'Event Support',
    'Pet Care',
    'Other',
  ];

  final Set<String> _selected = {};
  double _radius = 5.0;
  bool _saving = false;

  // Edit-rate limit keys
  static const _kWindowStart = 'zancrew_prefs_window_start_ms';
  static const _kEditCount = 'zancrew_prefs_edits_in_window';

  @override
  void initState() {
    super.initState();
    _ensureLoggedIn();
    _prefillFromPrefs();
  }

  // ---------------------------------------------------------------------------
  // PRE-CHECK: Ensure user is logged in (must have user_id + phone saved)
  // ---------------------------------------------------------------------------
  Future<void> _ensureLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_phone');
    final userId = prefs.getString('user_id');

    if (phone == null || phone.isEmpty || userId == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please sign in first')));
      Navigator.pop(context);
    }
  }

  // ---------------------------------------------------------------------------
  // PREFILL existing preferences (if any)
  // ---------------------------------------------------------------------------
  Future<void> _prefillFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final buckets = prefs.getStringList('zancrew_buckets') ?? <String>[];
    final radius = prefs.getDouble('zancrew_radius_km') ?? 5.0;

    setState(() {
      _selected.addAll(buckets);
      _radius = radius;
    });
  }

  // ---------------------------------------------------------------------------
  // WEEKLY EDIT LIMIT — Only applies when user edits (not first-time)
  // ---------------------------------------------------------------------------
  Future<bool> _checkEditQuota() async {
    if (!widget.editMode) return true;

    final prefs = await SharedPreferences.getInstance();
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    final startMs = prefs.getInt(_kWindowStart);
    int count = prefs.getInt(_kEditCount) ?? 0;

    if (startMs == null) {
      await prefs.setInt(_kWindowStart, nowMs);
      await prefs.setInt(_kEditCount, 0);
      return true;
    }

    final start = DateTime.fromMillisecondsSinceEpoch(startMs);
    if (DateTime.now().difference(start).inDays >= 7) {
      await prefs.setInt(_kWindowStart, nowMs);
      await prefs.setInt(_kEditCount, 0);
      return true;
    }

    return count < 2;
  }

  Future<void> _incrementEditCount() async {
    if (!widget.editMode) return;
    final prefs = await SharedPreferences.getInstance();
    final count = prefs.getInt(_kEditCount) ?? 0;
    await prefs.setInt(_kEditCount, count + 1);
  }

  // ---------------------------------------------------------------------------
  // SAVE PREFERENCES (first-time OR edit)
  // ---------------------------------------------------------------------------
  Future<void> _save() async {
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick at least one category')),
      );
      return;
    }

    if (widget.editMode) {
      final ok = await _checkEditQuota();
      if (!ok) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('You can only change preferences twice per week.'),
          ),
        );
        return;
      }
    }

    setState(() => _saving = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      if (userId == null) throw Exception('Not signed in');

      final status = widget.editMode ? 'active' : 'pending';

      // Push to backend
      await ZanCrewApi.upsertProfile(
        userId: userId,
        buckets: _selected.toList(),
        radiusKm: _radius.round(),
        status: status,
      );

      // Local storage sync
      await prefs.setStringList('zancrew_buckets', _selected.toList());
      await prefs.setDouble('zancrew_radius_km', _radius);
      await prefs.setString('zancrew_status', status);
      await prefs.setBool('zancrew_enabled', status == 'active');

      await _incrementEditCount();

      if (!mounted) return;

      // Navigation
      if (widget.editMode) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Preferences updated.')));
        Navigator.pop(context, true);
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const UkWorkStatusScreen()),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Something went wrong. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final isEdit = widget.editMode;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: _ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          isEdit ? 'Edit Preferences' : 'Join ZanCrew',
          style: const TextStyle(
            color: _ink,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          children: [
            if (!isEdit) ...[
              const SizedBox(height: 8),
              const Text(
                'Choose how you can help',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                "Pick the services you're comfortable with and how far you're happy to travel.",
                style: TextStyle(fontSize: 15, color: _muted, height: 1.4),
              ),
              const SizedBox(height: 28),
            ] else ...[
              const SizedBox(height: 12),
            ],

            // ----- CATEGORY PICKER -----
            const Text(
              'Your skills',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _allBuckets.map((b) {
                final sel = _selected.contains(b);
                return ChoiceChip(
                  label: Text(b),
                  selected: sel,
                  selectedColor: const Color(0xFFFEF3C7),
                  backgroundColor: Colors.white,
                  side: BorderSide(
                    color: sel ? _accent : _border,
                    width: sel ? 1.5 : 1.0,
                  ),
                  checkmarkColor: _accent,
                  labelStyle: TextStyle(
                    color: sel ? _accent : _ink,
                    fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                    fontSize: 13.5,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  onSelected: (_) {
                    setState(() {
                      sel ? _selected.remove(b) : _selected.add(b);
                    });
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: 28),

            // ----- RADIUS -----
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Service radius',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
                Text(
                  '${_radius.round()} km',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: _accent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SliderTheme(
              data: SliderThemeData(
                activeTrackColor: _accent,
                inactiveTrackColor: _border,
                thumbColor: _accent,
                overlayColor: const Color(0xFFD97706).withValues(alpha: 0.12),
                trackHeight: 3,
              ),
              child: Slider(
                min: 1,
                max: 50,
                divisions: 49,
                label: '${_radius.round()} km',
                value: _radius,
                onChanged: (v) => setState(() => _radius = v),
              ),
            ),

            const SizedBox(height: 32),

            SizedBox(
              height: 52,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  disabledBackgroundColor: _border,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : Text(
                        isEdit ? 'Save Changes' : 'Continue to Right to Work',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15.5,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
