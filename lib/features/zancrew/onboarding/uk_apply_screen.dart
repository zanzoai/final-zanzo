// lib/features/zancrew/onboarding/uk_apply_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/uk_provider_api.dart';
import 'uk_hold_screen.dart';
import 'uk_pending_screen.dart';
import 'uk_rejected_screen.dart';

class UkApplyScreen extends StatefulWidget {
  final String workStatus;
  final bool requiresShareCode;

  const UkApplyScreen({
    super.key,
    required this.workStatus,
    required this.requiresShareCode,
  });

  @override
  State<UkApplyScreen> createState() => _UkApplyScreenState();
}

class _UkApplyScreenState extends State<UkApplyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _shareCodeCtrl = TextEditingController();
  final _universityCtrl = TextEditingController();
  final _courseCtrl = TextEditingController();
  final _visaExpiryCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  bool _termsAgreed = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  Future<void> _prefill() async {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('user_phone');
    if (phone != null && mounted) _phoneCtrl.text = phone;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _dobCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _shareCodeCtrl.dispose();
    _universityCtrl.dispose();
    _courseCtrl.dispose();
    _visaExpiryCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_termsAgreed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please agree to the terms and conditions.')),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id') ?? '';
      if (userId.isEmpty) throw Exception('Not signed in');

      final result = await UkProviderApi.apply(
        userId: userId,
        declaredWorkStatus: widget.workStatus,
        fullName: _nameCtrl.text.trim(),
        dateOfBirth: _dobCtrl.text.trim().isNotEmpty ? _dobCtrl.text.trim() : null,
        phone: _phoneCtrl.text.trim().isNotEmpty ? _phoneCtrl.text.trim() : null,
        addressOrPostcode: _addressCtrl.text.trim().isNotEmpty
            ? _addressCtrl.text.trim()
            : null,
        shareCode: _shareCodeCtrl.text.trim().isNotEmpty
            ? _shareCodeCtrl.text.trim()
            : null,
        termsAgreed: true,
        universityName: _universityCtrl.text.trim().isNotEmpty
            ? _universityCtrl.text.trim()
            : null,
        courseName: _courseCtrl.text.trim().isNotEmpty
            ? _courseCtrl.text.trim()
            : null,
        visaExpiryDate: _visaExpiryCtrl.text.trim().isNotEmpty
            ? _visaExpiryCtrl.text.trim()
            : null,
        applicantNotes: _notesCtrl.text.trim().isNotEmpty
            ? _notesCtrl.text.trim()
            : null,
      );

      if (!mounted) return;

      const holdStatuses = {'student_visa', 'skilled_worker_or_other', 'unknown'};
      final providerStatus = result['provider_status'] as String? ?? 'pending';
      final declaredStatus =
          result['declared_work_status'] as String? ?? widget.workStatus;

      if (providerStatus == 'rejected') {
        if (holdStatuses.contains(declaredStatus)) {
          final msg = result['message'] as String? ??
              result['rejection_reason'] as String?;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => UkHoldScreen(reason: msg),
            ),
          );
        } else {
          final reason = result['rejection_reason'] as String?;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => UkRejectedScreen(
                status: 'rejected',
                reason: reason,
              ),
            ),
          );
        }
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const UkPendingScreen()),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Submission failed: $e')),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String get _statusLabel {
    switch (widget.workStatus) {
      case 'british_irish':
        return 'British / Irish citizen';
      case 'settled_pre_settled':
        return 'EU Settled or Pre-Settled Status';
      case 'graduate_visa':
        return 'Graduate Visa';
      case 'skilled_worker_or_other':
        return 'Skilled Worker / restricted work visa';
      case 'student_visa':
        return 'Student Visa';
      case 'unknown':
        return 'Other visa / I\'m not sure';
      default:
        return widget.workStatus;
    }
  }

  String get _helpText {
    switch (widget.workStatus) {
      case 'british_irish':
        return 'Your details will be reviewed manually by our team. Please provide your full legal name as it appears on your passport.';
      case 'settled_pre_settled':
      case 'graduate_visa':
        return 'Please provide your GOV.UK share code. We will verify your right to work.';
      case 'skilled_worker_or_other':
        return 'Please provide your GOV.UK share code. This route may have work restrictions, so we\'ll review your details before paid tasks are enabled.';
      case 'student_visa':
        return 'Please provide your GOV.UK share code and student details. We\'ll keep your application ready for a future student route.';
      case 'unknown':
        return 'Tell us your details and we\'ll help determine your right-to-work route. We may ask for more evidence before paid tasks can be enabled.';
      default:
        return 'Please provide your details.';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Provider Application'),
        backgroundColor: Colors.orangeAccent,
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orangeAccent),
                ),
                child: Text(
                  'Status: $_statusLabel\n\n$_helpText',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(height: 24),
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Full Name *',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Full name is required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _dobCtrl,
                decoration: const InputDecoration(
                  labelText: 'Date of Birth (YYYY-MM-DD) *',
                  border: OutlineInputBorder(),
                  hintText: '1990-01-31',
                ),
                keyboardType: TextInputType.datetime,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) return 'Date of birth is required';
                  if (DateTime.tryParse(v.trim()) == null) return 'Use format YYYY-MM-DD';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _phoneCtrl,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _addressCtrl,
                decoration: const InputDecoration(
                  labelText: 'Address or Postcode *',
                  border: OutlineInputBorder(),
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Address or postcode is required' : null,
              ),
              if (widget.requiresShareCode) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _shareCodeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'GOV.UK Share Code *',
                    border: OutlineInputBorder(),
                    hintText: 'e.g. W1A1AA',
                    helperText: 'Get your code at gov.uk/prove-right-to-work',
                  ),
                  textCapitalization: TextCapitalization.characters,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Share code is required for your visa type';
                    }
                    return null;
                  },
                ),
              ],
              if (widget.workStatus == 'student_visa') ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _universityCtrl,
                  decoration: const InputDecoration(
                    labelText: 'University Name *',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.words,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'University name is required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _courseCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Course Name *',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.words,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Course name is required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _visaExpiryCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Visa Expiry Date (YYYY-MM-DD)',
                    border: OutlineInputBorder(),
                    hintText: '2026-12-31',
                  ),
                  keyboardType: TextInputType.datetime,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    if (DateTime.tryParse(v.trim()) == null) return 'Use format YYYY-MM-DD';
                    return null;
                  },
                ),
              ],
              if (widget.workStatus == 'unknown' ||
                  widget.workStatus == 'skilled_worker_or_other') ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _notesCtrl,
                  decoration: InputDecoration(
                    labelText: widget.workStatus == 'unknown'
                        ? 'Tell us about your visa or right-to-work proof'
                        : 'Any extra details about your work restrictions? (optional)',
                    border: const OutlineInputBorder(),
                  ),
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ],
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: _termsAgreed,
                    onChanged: (v) => setState(() => _termsAgreed = v ?? false),
                    activeColor: Colors.orangeAccent,
                  ),
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'I confirm the information I have provided is accurate and agree to the terms and conditions.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orangeAccent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Submit Application',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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
