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
  // -----------------------------------------------
  // CATALOG + STATE
  // -----------------------------------------------
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please sign in first")),
      );
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
        const SnackBar(content: Text("Pick at least one category")),
      );
      return;
    }

    if (widget.editMode) {
      final ok = await _checkEditQuota();
      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("You can only change preferences twice per week."),
          ),
        );
        return;
      }
    }

    setState(() => _saving = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      if (userId == null) throw Exception("Not signed in");

      final status = widget.editMode ? "active" : "pending";

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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Preferences updated.")),
        );
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Preferences saved. Continue to right-to-work check.")),
        );
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => const UkWorkStatusScreen(),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Failed: $e")));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final title = widget.editMode
        ? "Edit ZanCrew Preferences"
        : "Join ZanCrew";
    final cta = widget.editMode
        ? "Save Changes"
        : "Continue to Right to Work";

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        backgroundColor: Colors.orangeAccent,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            Text(
              widget.editMode
                  ? "Update your choices"
                  : "Pick what you’re great at and how far you’ll travel.",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 20),

            // ----- CATEGORY PICKER -----
            const Text(
              "Your skills",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _allBuckets.map((b) {
                final selected = _selected.contains(b);
                return ChoiceChip(
                  label: Text(b),
                  selected: selected,
                  onSelected: (_) {
                    setState(() {
                      selected ? _selected.remove(b) : _selected.add(b);
                    });
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: 24),

            // ----- RADIUS -----
            const Text(
              "Service radius (km)",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            Slider(
              min: 1,
              max: 50,
              divisions: 49,
              label: "${_radius.round()} km",
              value: _radius,
              onChanged: (v) => setState(() => _radius = v),
            ),

            const SizedBox(height: 24),

            ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(cta),
            ),
          ],
        ),
      ),
    );
  }
}