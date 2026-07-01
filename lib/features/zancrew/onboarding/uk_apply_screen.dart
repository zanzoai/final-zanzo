// lib/features/zancrew/onboarding/uk_apply_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/uk_provider_api.dart';
import 'uk_document_upload_screen.dart';
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
  static const _bg = Color(0xFFFCFAF6);
  static const _ink = Color(0xFF26211C);
  static const _muted = Color(0xFF9B8B7E);
  static const _accent = Color(0xFFD97706);
  static const _border = Color(0xFFE8E2D9);

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

  // ---------------------------------------------------------------------------
  // SUBMIT — routing/backend logic unchanged
  // ---------------------------------------------------------------------------
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_termsAgreed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please agree to the terms and conditions.'),
        ),
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
        dateOfBirth: _dobCtrl.text.trim().isNotEmpty
            ? _dobCtrl.text.trim()
            : null,
        phone: _phoneCtrl.text.trim().isNotEmpty
            ? _phoneCtrl.text.trim()
            : null,
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

      const holdStatuses = {
        'student_visa',
        'skilled_worker_or_other',
        'unknown',
      };
      final providerStatus = result['provider_status'] as String? ?? 'pending';
      final declaredStatus =
          result['declared_work_status'] as String? ?? widget.workStatus;

      if (providerStatus == 'rejected') {
        if (holdStatuses.contains(declaredStatus)) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => const UkHoldScreen()),
          );
        } else {
          final reason = result['rejection_reason'] as String?;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  UkRejectedScreen(status: 'rejected', reason: reason),
            ),
          );
        }
      } else if (widget.workStatus == 'british_irish') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const UkDocumentUploadScreen()),
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
        const SnackBar(
          content: Text('Something went wrong. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ---------------------------------------------------------------------------
  // HELPERS — copy unchanged
  // ---------------------------------------------------------------------------
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
        return "Other visa / I'm not sure";
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
        return "Please provide your GOV.UK share code. This route may have work restrictions, so we'll review your details before paid tasks are enabled.";
      case 'student_visa':
        return "Please provide your GOV.UK share code and student details.";
      case 'unknown':
        return "Tell us your details and we'll help determine your right-to-work route.";
      default:
        return 'Please provide your details.';
    }
  }

  // ---------------------------------------------------------------------------
  // FORM FIELD DECORATION HELPER
  // ---------------------------------------------------------------------------
  InputDecoration _dec(String label, {String? hint, String? helperText}) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helperText,
      helperMaxLines: 3,
      filled: true,
      fillColor: Colors.white,
      labelStyle: const TextStyle(color: _muted),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red, width: 1.5),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text(
          'Provider Application',
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
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            children: [
              // Status label
              Text(
                _statusLabel,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _muted,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 10),

              // Info banner
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8E8),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, size: 18, color: _accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _helpText,
                        style: const TextStyle(
                          fontSize: 13,
                          color: _ink,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Student-specific notice
              if (widget.workStatus == 'student_visa') ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _border),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.school_outlined, size: 18, color: _accent),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Student work permissions can depend on your visa conditions, course dates, and term-time limits. We\'ll review your details before activating paid tasks.',
                          style: TextStyle(
                            fontSize: 13,
                            color: _ink,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),

              // Full name
              TextFormField(
                controller: _nameCtrl,
                decoration: _dec(
                  'Full Name *',
                  hint: 'As it appears on your ID document',
                  helperText:
                      'Use your full legal name as it appears on your right-to-work document. This should also match your payout bank account.',
                ),
                textCapitalization: TextCapitalization.words,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Full name is required'
                    : null,
              ),
              const SizedBox(height: 16),

              // Date of birth
              TextFormField(
                controller: _dobCtrl,
                decoration: _dec('Date of Birth *', hint: '1990-01-31'),
                keyboardType: TextInputType.datetime,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Date of birth is required';
                  }
                  if (DateTime.tryParse(v.trim()) == null) {
                    return 'Use format YYYY-MM-DD';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Phone
              TextFormField(
                controller: _phoneCtrl,
                decoration: _dec('Phone'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 16),

              // Address
              TextFormField(
                controller: _addressCtrl,
                decoration: _dec('Address or Postcode *'),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? 'Address or postcode is required'
                    : null,
              ),

              // Share code
              if (widget.requiresShareCode) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _shareCodeCtrl,
                  decoration: _dec(
                    'GOV.UK Share Code *',
                    hint: 'e.g. W1A1AA',
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

              // Student-specific fields
              if (widget.workStatus == 'student_visa') ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _universityCtrl,
                  decoration: _dec('University Name *'),
                  textCapitalization: TextCapitalization.words,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'University name is required'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _courseCtrl,
                  decoration: _dec('Course Name *'),
                  textCapitalization: TextCapitalization.words,
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? 'Course name is required'
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _visaExpiryCtrl,
                  decoration: _dec(
                    'Visa Expiry Date (YYYY-MM-DD)',
                    hint: '2026-12-31',
                  ),
                  keyboardType: TextInputType.datetime,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    if (DateTime.tryParse(v.trim()) == null) {
                      return 'Use format YYYY-MM-DD';
                    }
                    return null;
                  },
                ),
              ],

              // Notes for unknown / skilled_worker
              if (widget.workStatus == 'unknown' ||
                  widget.workStatus == 'skilled_worker_or_other') ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _notesCtrl,
                  decoration: _dec(
                    widget.workStatus == 'unknown'
                        ? 'Tell us about your visa or right-to-work proof'
                        : 'Any extra details about your work restrictions? (optional)',
                  ),
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ],

              const SizedBox(height: 24),

              // Terms checkbox
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: _termsAgreed,
                    activeColor: _accent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                    onChanged: (v) => setState(() => _termsAgreed = v ?? false),
                  ),
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(top: 12),
                      child: Text(
                        'I confirm the information I have provided is accurate and agree to the terms and conditions.',
                        style: TextStyle(
                          fontSize: 13,
                          color: _ink,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    disabledBackgroundColor: _border,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          'Submit Application',
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                          ),
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
