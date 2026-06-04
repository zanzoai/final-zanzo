// lib/features/zancrew/onboarding/uk_apply_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/uk_provider_api.dart';
import 'uk_pending_screen.dart';
import 'uk_student_blocked_screen.dart';

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
      );

      if (!mounted) return;

      final providerStatus = result['provider_status'] as String? ?? 'pending';
      if (providerStatus == 'rejected') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const UkStudentBlockedScreen()),
        );
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
        return 'Skilled Worker or other visa';
      default:
        return widget.workStatus;
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
                  'Status: $_statusLabel\n\n'
                  '${widget.workStatus == 'british_irish' ? 'Your details will be reviewed manually by our team. Please provide your full legal name as it appears on your passport.' : 'Please provide your GOV.UK share code. We will verify your right to work at gov.uk/prove-right-to-work.'}',
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
                        'I confirm that I am working as an independent self-employed provider and agree to the terms and conditions. I declare that the information provided is accurate.',
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
