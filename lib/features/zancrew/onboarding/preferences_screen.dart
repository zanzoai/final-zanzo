// -----------------------------------------------------------------------------
// ZanCrew Onboarding — PREFERENCES SCREEN
//
// Purpose:
//  1) Let the user select the job categories (buckets) they are willing to work in
//  2) Let the user choose travel radius (3km / 5km / 10km or slider up to 25km)
//  3) Save preferences to SharedPreferences
//  4) Send preferences to backend (status = "pending" on first setup)
//  5) Navigate to → UkWorkStatusScreen
//
// File: lib/features/zancrew/onboarding/preferences_screen.dart
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zanzo_frontend/core/services/zancrew_api.dart';

import 'uk_work_status_screen.dart';

class ZanCrewPreferencesScreen extends StatefulWidget {
  const ZanCrewPreferencesScreen({super.key});

  @override
  State<ZanCrewPreferencesScreen> createState() =>
      _ZanCrewPreferencesScreenState();
}

class _ZanCrewPreferencesScreenState extends State<ZanCrewPreferencesScreen> {
  // ---------------------------------------------------------------------------
  // Skill categories (buckets)
  // ---------------------------------------------------------------------------
  static const List<String> _skillCatalog = [
    'Delivery',
    'On-site Helper',
    'Cleaning',
    'Furniture Moving',
    'Electrician Help',
    'Packing & Shifting',
    'Event Assistance',
    'Pick & Drop Items',
    'Queue / Stand-in-line',
  ];

  final Set<String> _selectedSkills = {};
  double _radiusKm = 5;
  bool _saving = false;

  // ---------------------------------------------------------------------------
  // SAVE PREFERENCES → local + backend → go to KYC intro screen
  // ---------------------------------------------------------------------------
  Future<void> _saveAndContinue() async {
    if (_selectedSkills.isEmpty) return;

    setState(() => _saving = true);

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');

    if (userId == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Please sign in first.")));
      }
      return;
    }

    // Save locally
    await prefs.setStringList(
      'zancrew_buckets',
      _selectedSkills.toList()..sort(),
    );
    await prefs.setDouble('zancrew_radius_km', _radiusKm);

    // Backend (first onboarding → pending)
    try {
      await ZanCrewApi.upsertProfile(
        userId: userId,
        buckets: _selectedSkills.toList(),
        radiusKm: _radiusKm.round(),
        status: "pending",
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Saved locally, backend failed: $e"),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }

    setState(() => _saving = false);
    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const UkWorkStatusScreen()),
    );
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final canContinue = _selectedSkills.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Work Preferences'),
        backgroundColor: Colors.orangeAccent,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              const Text(
                'Select the type of jobs you are willing to do',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 14),

              // Skill selection chips
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _skillCatalog.map((skill) {
                  final selected = _selectedSkills.contains(skill);
                  return FilterChip(
                    label: Text(skill),
                    selected: selected,
                    onSelected: (v) {
                      setState(() {
                        v
                            ? _selectedSkills.add(skill)
                            : _selectedSkills.remove(skill);
                      });
                    },
                    selectedColor: Colors.orangeAccent.withOpacity(0.25),
                    checkmarkColor: Colors.orange,
                  );
                }).toList(),
              ),

              const SizedBox(height: 30),
              const Divider(),
              const SizedBox(height: 10),

              // Radius selection
              const Text(
                'How far are you willing to travel?',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),

              Row(
                children: [3, 5, 10].map((km) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('$km km'),
                      selected: _radiusKm.round() == km,
                      onSelected: (_) {
                        setState(() => _radiusKm = km.toDouble());
                      },
                      selectedColor: Colors.orangeAccent.withOpacity(0.2),
                    ),
                  );
                }).toList(),
              ),

              Slider(
                value: _radiusKm,
                min: 1,
                max: 25,
                divisions: 24,
                label: '${_radiusKm.toStringAsFixed(0)} km',
                onChanged: (v) => setState(() => _radiusKm = v),
              ),
              Text(
                '${_radiusKm.toStringAsFixed(0)} km selected',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),

              const Spacer(),

              // Continue button
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: canContinue && !_saving ? _saveAndContinue : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: canContinue
                        ? Colors.orangeAccent
                        : Colors.grey,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Continue',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
