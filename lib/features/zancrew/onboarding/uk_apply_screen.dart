// lib/features/zancrew/onboarding/uk_apply_screen.dart
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/uk_provider_api.dart';
import 'uk_pending_screen.dart';
import 'uk_rejected_screen.dart';

/// Valid course levels accepted by the backend.
const _courseLevels = [
  'undergraduate',
  'postgraduate',
  'foundation',
  'phd',
  'other',
];

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

  // Core fields
  final _nameCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _shareCodeCtrl = TextEditingController();
  final _niCtrl = TextEditingController();

  // Student-visa fields
  final _uniCtrl = TextEditingController();
  final _courseCtrl = TextEditingController();
  final _visaExpiryCtrl = TextEditingController();
  final _otherHoursCtrl = TextEditingController();
  String? _selectedCourseLevel;
  File? _termEvidenceFile;
  String? _termEvidenceFileName;
  bool _uploadingEvidence = false;

  bool _termsAgreed = false;
  bool _submitting = false;

  bool get _isStudent => widget.workStatus == 'student_visa';

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
    _niCtrl.dispose();
    _uniCtrl.dispose();
    _courseCtrl.dispose();
    _visaExpiryCtrl.dispose();
    _otherHoursCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickTermEvidence() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf', 'docx'],
    );
    if (result == null || result.files.single.path == null) return;
    setState(() {
      _termEvidenceFile = File(result.files.single.path!);
      _termEvidenceFileName = result.files.single.name;
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_isStudent && _termEvidenceFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Please upload your term/vacation-date evidence before submitting.')),
      );
      return;
    }

    if (!_termsAgreed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Please read and agree to the terms before submitting.')),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id') ?? '';
      if (userId.isEmpty) throw Exception('Not signed in');

      // Students must upload term_time_evidence before the backend will accept
      // their application (evidence gate in apply()). Upload first.
      if (_isStudent && _termEvidenceFile != null) {
        setState(() => _uploadingEvidence = true);
        await UkProviderApi.uploadDocument(
          file: _termEvidenceFile!,
          documentType: 'term_time_evidence',
        );
        if (mounted) setState(() => _uploadingEvidence = false);
      }

      final otherHours = _otherHoursCtrl.text.trim().isNotEmpty
          ? int.tryParse(_otherHoursCtrl.text.trim())
          : null;

      final result = await UkProviderApi.apply(
        userId: userId,
        declaredWorkStatus: widget.workStatus,
        fullName: _nameCtrl.text.trim(),
        dateOfBirth:
            _dobCtrl.text.trim().isNotEmpty ? _dobCtrl.text.trim() : null,
        phone: _phoneCtrl.text.trim().isNotEmpty
            ? _phoneCtrl.text.trim()
            : null,
        addressOrPostcode: _addressCtrl.text.trim().isNotEmpty
            ? _addressCtrl.text.trim()
            : null,
        shareCode: _shareCodeCtrl.text.trim().isNotEmpty
            ? _shareCodeCtrl.text.trim()
            : null,
        niNumber: _niCtrl.text.trim().isNotEmpty ? _niCtrl.text.trim() : null,
        universityName: _isStudent ? _uniCtrl.text.trim() : null,
        courseName: _isStudent ? _courseCtrl.text.trim() : null,
        courseLevel: _isStudent ? _selectedCourseLevel : null,
        visaExpiryDate: _isStudent && _visaExpiryCtrl.text.trim().isNotEmpty
            ? _visaExpiryCtrl.text.trim()
            : null,
        otherEmploymentHoursPerWeek: _isStudent ? otherHours : null,
        termsAgreed: true,
      );

      if (!mounted) return;

      final providerStatus =
          result['provider_status'] as String? ?? 'pending';
      final rejectionReason = result['rejection_reason'] as String?;
      final message = result['message'] as String?;

      if (providerStatus == 'rejected') {
        // Student route disabled or other ineligible status: show reason.
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => UkRejectedScreen(
              status: providerStatus,
              reason: rejectionReason ?? message,
            ),
          ),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const UkPendingScreen()),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _uploadingEvidence = false);
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
      case 'student_visa':
        return 'Student Visa (PAYE)';
      default:
        return widget.workStatus;
    }
  }

  String get _statusInfoText {
    if (_isStudent) {
      return 'Student Visa holders work as PAYE employees, not independent '
          'providers. Your application will be reviewed by our team, and work '
          'is subject to your visa\'s weekly hours limit.\n\n'
          'You must upload evidence of your university term/vacation dates '
          'below before submitting.';
    }
    if (widget.workStatus == 'british_irish') {
      return 'Your details will be reviewed manually by our team. '
          'Please provide your full legal name as it appears on your passport.';
    }
    return 'Please provide your GOV.UK share code. We will verify your right '
        'to work at gov.uk/prove-right-to-work.';
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
              // Status info banner
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _isStudent
                      ? Colors.amber.shade50
                      : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color:
                          _isStudent ? Colors.amber : Colors.orangeAccent),
                ),
                child: Text(
                  'Status: $_statusLabel\n\n$_statusInfoText',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(height: 24),

              // ── Core fields ──────────────────────────────────────────────
              TextFormField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Full Name *',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    (v == null || v.trim().isEmpty)
                        ? 'Full name is required'
                        : null,
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
                    (v == null || v.trim().isEmpty)
                        ? 'Address or postcode is required'
                        : null,
              ),
              const SizedBox(height: 16),

              // NI number (all workers)
              TextFormField(
                controller: _niCtrl,
                decoration: const InputDecoration(
                  labelText: 'National Insurance Number',
                  border: OutlineInputBorder(),
                  hintText: 'e.g. AB123456C',
                  helperText: 'Required for HMRC payroll. Leave blank if unknown.',
                ),
                textCapitalization: TextCapitalization.characters,
              ),

              // Share code (visa holders)
              if (widget.requiresShareCode) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _shareCodeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'GOV.UK Share Code *',
                    border: OutlineInputBorder(),
                    hintText: 'e.g. W1A1AA',
                    helperText:
                        'Get your code at gov.uk/prove-right-to-work',
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

              // ── Student-only fields ──────────────────────────────────────
              if (_isStudent) ...[
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 8),
                const Text(
                  'Student Details',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _uniCtrl,
                  decoration: const InputDecoration(
                    labelText: 'University / Institution *',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.words,
                  validator: (v) =>
                      (v == null || v.trim().isEmpty)
                          ? 'University name is required'
                          : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _courseCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Course / Programme',
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Course Level *',
                    border: OutlineInputBorder(),
                  ),
                  value: _selectedCourseLevel,
                  items: _courseLevels
                      .map((l) => DropdownMenuItem(
                            value: l,
                            child: Text(
                                l[0].toUpperCase() + l.substring(1)),
                          ))
                      .toList(),
                  onChanged: (v) =>
                      setState(() => _selectedCourseLevel = v),
                  validator: (v) =>
                      v == null ? 'Course level is required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _visaExpiryCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Visa Expiry Date (YYYY-MM-DD)',
                    border: OutlineInputBorder(),
                    hintText: '2026-09-30',
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
                const SizedBox(height: 16),
                TextFormField(
                  controller: _otherHoursCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Hours per week with other employers',
                    border: OutlineInputBorder(),
                    hintText: '0',
                    helperText:
                        'Enter 0 if you have no other employment. Used to calculate your remaining weekly capacity.',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    final n = int.tryParse(v.trim());
                    if (n == null || n < 0) {
                      return 'Enter a number 0 or greater';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // Term/vacation evidence upload — required by backend before apply
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.upload_file,
                              color: Colors.amber.shade700),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Term / Vacation Evidence *',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Upload a letter from your university confirming your term dates, '
                        'or vacation confirmation. Accepted: JPEG, PNG, PDF, DOCX (max 10 MB).',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 10),
                      if (_termEvidenceFileName != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Icon(Icons.check_circle,
                                  color: Colors.green.shade600, size: 18),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  _termEvidenceFileName!,
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.green.shade700),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      OutlinedButton.icon(
                        onPressed: _uploadingEvidence ? null : _pickTermEvidence,
                        icon: const Icon(Icons.attach_file),
                        label: Text(_termEvidenceFileName == null
                            ? 'Choose file'
                            : 'Replace file'),
                      ),
                    ],
                  ),
                ),
              ],

              // ── Terms ────────────────────────────────────────────────────
              const SizedBox(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Checkbox(
                    value: _termsAgreed,
                    onChanged: (v) =>
                        setState(() => _termsAgreed = v ?? false),
                    activeColor: Colors.orangeAccent,
                  ),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _isStudent
                            ? 'I confirm that I hold a valid Student Visa and consent to '
                              'Zanzo verifying my right to work. I understand I will be '
                              'engaged as a PAYE employee subject to my visa\'s weekly '
                              'working-hours limit, and that my hours will be monitored. '
                              'I declare that all information provided is accurate.'
                            : 'I confirm that I am working as an independent self-employed '
                              'provider and agree to the terms and conditions. I declare '
                              'that the information provided is accurate.',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_submitting || _uploadingEvidence) ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orangeAccent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: (_submitting || _uploadingEvidence)
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(_uploadingEvidence
                                ? 'Uploading evidence…'
                                : 'Submitting…'),
                          ],
                        )
                      : const Text(
                          'Submit Application',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700),
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
