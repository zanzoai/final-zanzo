// lib/features/zancrew/onboarding/uk_apply_screen.dart
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/uk_provider_api.dart';
import 'uk_document_upload_screen.dart';
import 'uk_hold_screen.dart';
import 'uk_pending_screen.dart';
import 'uk_rejected_screen.dart';

enum _EvidenceStatus { idle, uploading, done, failed }

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

  static const _success = Color(0xFF16A34A);

  // Course level dropdown options for student_visa.
  static const _courseLevelOptions = [
    ('undergraduate', 'Undergraduate'),
    ('postgraduate', 'Postgraduate'),
    ('foundation', 'Foundation / Access'),
    ('phd', 'PhD / Research'),
    ('other', 'Other'),
  ];

  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _shareCodeCtrl = TextEditingController();
  final _universityCtrl = TextEditingController();
  final _courseCtrl = TextEditingController();
  final _visaExpiryCtrl = TextEditingController();
  final _otherEmploymentCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  String? _courseLevel;

  // Term evidence upload state (student_visa only).
  File? _evidenceFile;
  String? _evidenceFileName;
  _EvidenceStatus _evidenceStatus = _EvidenceStatus.idle;
  String? _evidenceError;

  bool get _evidenceDone => _evidenceStatus == _EvidenceStatus.done;
  bool get _requiresEvidence => widget.workStatus == 'student_visa';
  bool get _canSubmit => !_requiresEvidence || _evidenceDone;

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
    _otherEmploymentCtrl.dispose();
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
    if (_requiresEvidence && !_evidenceDone) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Please upload your term/vacation-date evidence before submitting.'),
        ),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id') ?? '';
      if (userId.isEmpty) throw Exception('Not signed in');

      final otherHoursText = _otherEmploymentCtrl.text.trim();
      final otherHours = otherHoursText.isNotEmpty
          ? int.tryParse(otherHoursText)
          : null;

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
        courseLevel: _courseLevel,
        visaExpiryDate: _visaExpiryCtrl.text.trim().isNotEmpty
            ? _visaExpiryCtrl.text.trim()
            : null,
        otherEmploymentHoursPerWeek: otherHours,
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
  // EVIDENCE UPLOAD
  // ---------------------------------------------------------------------------
  Future<void> _pickAndUploadEvidence() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'docx', 'doc', 'jpg', 'jpeg', 'png'],
        withData: false,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open file picker. Please try again.')),
      );
      return;
    }

    if (result == null || result.files.isEmpty) return;
    final pf = result.files.single;
    if (pf.path == null) return;

    setState(() {
      _evidenceFile = File(pf.path!);
      _evidenceFileName = pf.name;
      _evidenceStatus = _EvidenceStatus.uploading;
      _evidenceError = null;
    });

    try {
      await UkProviderApi.uploadDocument(
        documentType: 'term_time_evidence',
        file: _evidenceFile!,
      );
      if (!mounted) return;
      setState(() => _evidenceStatus = _EvidenceStatus.done);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _evidenceStatus = _EvidenceStatus.failed;
        _evidenceError = 'Upload failed. Please try again.';
      });
    }
  }

  Widget _evidenceUploadCard() {
    final isDone = _evidenceStatus == _EvidenceStatus.done;
    final isUploading = _evidenceStatus == _EvidenceStatus.uploading;
    final isFailed = _evidenceStatus == _EvidenceStatus.failed;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDone ? const Color(0xFFBBF7D0) : _border,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x08000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: isDone
                      ? const Color(0xFFECFDF5)
                      : const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isDone ? Icons.check : Icons.description_outlined,
                  size: 20,
                  color: isDone ? _success : _accent,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Term / Vacation-date Evidence *',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _ink),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'PDF, DOCX or image — max 10 MB',
                      style: TextStyle(fontSize: 12, color: _muted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Upload a document showing your term dates or vacation periods '
            '(e.g. university term calendar, letter from your institution).',
            style: TextStyle(fontSize: 13, color: _muted, height: 1.3),
          ),
          const SizedBox(height: 12),
          if (_evidenceFileName != null) ...[
            Row(
              children: [
                const Icon(Icons.attach_file, size: 16, color: _muted),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    _evidenceFileName!,
                    style: const TextStyle(fontSize: 13, color: _ink),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (isUploading)
            const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: _accent),
                ),
                SizedBox(width: 8),
                Text('Uploading…',
                    style: TextStyle(color: _accent, fontSize: 13)),
              ],
            )
          else if (isDone)
            Row(
              children: [
                const Icon(Icons.check_circle, color: _success, size: 18),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Uploaded',
                    style: TextStyle(
                        color: _success,
                        fontWeight: FontWeight.w600,
                        fontSize: 13),
                  ),
                ),
                TextButton.icon(
                  onPressed: _pickAndUploadEvidence,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Change'),
                  style: TextButton.styleFrom(
                    foregroundColor: _muted,
                    textStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            )
          else ...[
            if (isFailed && _evidenceError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline,
                        color: Colors.red, size: 16),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(_evidenceError!,
                          style: const TextStyle(
                              color: Colors.red, fontSize: 12)),
                    ),
                  ],
                ),
              ),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton.icon(
                onPressed: _pickAndUploadEvidence,
                icon: const Icon(Icons.upload_file_outlined, size: 18),
                label: Text(_evidenceFile == null
                    ? 'Choose File'
                    : 'Choose Different File'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _accent,
                  side: const BorderSide(color: _accent),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // DATE PICKERS
  // ---------------------------------------------------------------------------
  Future<void> _pickDob(BuildContext context) async {
    final now = DateTime.now();
    // lastDate = exactly 18 years ago — the picker itself blocks under-18 dates
    final latest18 = DateTime(now.year - 18, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 21, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: latest18,
    );
    if (picked == null) return;
    _dobCtrl.text =
        '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
  }

  Future<void> _pickVisaExpiry(BuildContext context) async {
    final now = DateTime.now();
    // Minimum 3 months from today — can't apply with an expiring visa
    final minExpiry = DateTime(now.year, now.month + 3, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year + 1, now.month, now.day),
      firstDate: minExpiry,
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    _visaExpiryCtrl.text =
        '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
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
                readOnly: true,
                onTap: () => _pickDob(context),
                decoration: _dec('Date of Birth *').copyWith(
                  suffixIcon: const Icon(Icons.calendar_today_outlined,
                      size: 20, color: _muted),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Date of birth is required';
                  }
                  final dob = DateTime.tryParse(v.trim());
                  if (dob == null) return 'Invalid date';
                  final now = DateTime.now();
                  final age = now.year - dob.year -
                      ((now.month < dob.month ||
                              (now.month == dob.month && now.day < dob.day))
                          ? 1
                          : 0);
                  if (age < 18) return 'You must be 18 or older to apply';
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
                // Course level dropdown
                DropdownButtonFormField<String>(
                  initialValue: _courseLevel,
                  decoration: _dec('Course Level *'),
                  items: _courseLevelOptions
                      .map((opt) => DropdownMenuItem(
                            value: opt.$1,
                            child: Text(opt.$2),
                          ))
                      .toList(),
                  onChanged: (v) => setState(() => _courseLevel = v),
                  validator: (v) =>
                      v == null ? 'Course level is required' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _visaExpiryCtrl,
                  readOnly: true,
                  onTap: () => _pickVisaExpiry(context),
                  decoration: _dec(
                    'Visa Expiry Date',
                    helperText:
                        'Your visa must be valid for at least 3 months from today.',
                  ).copyWith(
                    suffixIcon: const Icon(Icons.calendar_today_outlined,
                        size: 20, color: _muted),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _otherEmploymentCtrl,
                  decoration: _dec(
                    'Other employer hours per week',
                    hint: 'e.g. 8',
                    helperText:
                        'Hours you already work for other employers. Leave blank if none.',
                  ),
                  keyboardType: TextInputType.number,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return null;
                    final n = int.tryParse(v.trim());
                    if (n == null || n < 0) {
                      return 'Enter a whole number of hours (0 or more)';
                    }
                    return null;
                  },
                ),
                // Evidence upload card
                const SizedBox(height: 20),
                _evidenceUploadCard(),
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
                  onPressed: (_submitting || !_canSubmit) ? null : _submit,
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
