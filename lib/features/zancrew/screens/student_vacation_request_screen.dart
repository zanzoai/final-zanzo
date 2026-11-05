import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:zanzo_frontend/core/services/uk_provider_api.dart';

class StudentVacationRequestScreen extends StatefulWidget {
  const StudentVacationRequestScreen({super.key});

  @override
  State<StudentVacationRequestScreen> createState() =>
      _StudentVacationRequestScreenState();
}

class _StudentVacationRequestScreenState
    extends State<StudentVacationRequestScreen> {
  static const Color _accent = Color(0xFFD97706);
  static const Color _bg = Color(0xFFFCFAF6);
  static const Color _card = Colors.white;
  static const Color _ink = Color(0xFF26211C);
  static const Color _muted = Color(0xFF9B8B7E);
  static const Color _border = Color(0xFFE8E2D9);
  static const Color _success = Color(0xFF16A34A);

  DateTime? _startDate;
  DateTime? _endDate;

  String? _evidenceFileName;
  bool _uploading = false;
  bool _uploadDone = false;
  String? _evidenceError;
  String? _documentKey;

  bool _submitting = false;
  String? _error;
  bool _submitted = false;

  bool get _canSubmit =>
      _startDate != null &&
      _endDate != null &&
      !_submitting &&
      !_uploading;

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart
        ? (_startDate ?? DateTime.now())
        : (_endDate ?? (_startDate ?? DateTime.now()));
    final first = isStart ? DateTime.now() : (_startDate ?? DateTime.now());

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: first,
      lastDate: DateTime.now().add(const Duration(days: 730)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) {
          _endDate = null;
        }
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _pickAndUploadEvidence() async {
    setState(() {
      _uploading = true;
      _uploadDone = false;
      _evidenceError = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'docx', 'doc', 'jpg', 'jpeg', 'png'],
      );
      if (result == null || result.files.isEmpty) {
        setState(() => _uploading = false);
        return;
      }
      final path = result.files.first.path;
      if (path == null) {
        setState(() {
          _uploading = false;
          _evidenceError = 'Could not access the selected file.';
        });
        return;
      }
      final file = File(path);
      final res = await UkProviderApi.uploadDocument(
        documentType: 'vacation_evidence',
        file: file,
      );
      setState(() {
        _uploading = false;
        _uploadDone = true;
        _evidenceFileName = result.files.first.name;
        // The backend stores the key; we don't receive it directly from the
        // upload endpoint — the vacation-request endpoint looks it up server-side.
        _documentKey = res['storage_key'] as String?;
      });
    } catch (e) {
      setState(() {
        _uploading = false;
        _evidenceError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final startStr =
          '${_startDate!.year.toString().padLeft(4, '0')}-'
          '${_startDate!.month.toString().padLeft(2, '0')}-'
          '${_startDate!.day.toString().padLeft(2, '0')}';
      final endStr =
          '${_endDate!.year.toString().padLeft(4, '0')}-'
          '${_endDate!.month.toString().padLeft(2, '0')}-'
          '${_endDate!.day.toString().padLeft(2, '0')}';

      await UkProviderApi.submitVacationRequest(
        startDate: startStr,
        endDate: endStr,
        documentKey: _documentKey,
      );
      if (mounted) setState(() => _submitted = true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: _ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Request Vacation Hours',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: _submitted ? _buildSuccess() : _buildForm(),
    );
  }

  Widget _buildSuccess() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline, size: 64, color: _success),
            const SizedBox(height: 20),
            const Text(
              'Request submitted',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: _ink,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Your vacation work-hours request is under review.\n'
              'An admin will update you when a decision is made.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, height: 1.5),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'Done',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _infoCard(),
          const SizedBox(height: 20),
          _sectionLabel('Vacation dates'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _dateTile(
                  label: 'Start date',
                  date: _startDate,
                  onTap: () => _pickDate(isStart: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _dateTile(
                  label: 'End date',
                  date: _endDate,
                  onTap: () => _pickDate(isStart: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _sectionLabel('Evidence (optional)'),
          const SizedBox(height: 4),
          Text(
            'A letter from your university or a copy of your vacation schedule helps speed up approval.',
            style: TextStyle(fontSize: 13, color: _muted, height: 1.4),
          ),
          const SizedBox(height: 10),
          _evidenceCard(),
          const SizedBox(height: 28),
          if (_error != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _error!,
                style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 13),
              ),
            ),
            const SizedBox(height: 16),
          ],
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              onPressed: _canSubmit ? _submit : null,
              child: _submitting
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Submit request',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15.5,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: _accent, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'During approved vacation periods you can work up to the hours confirmed by the admin — usually above the standard 19 h/week term-time limit.',
              style: TextStyle(
                fontSize: 13,
                color: _ink,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        color: _ink,
      ),
    );
  }

  Widget _dateTile({
    required String label,
    required DateTime? date,
    required VoidCallback onTap,
  }) {
    final formatted = date == null
        ? 'Pick date'
        : '${date.day.toString().padLeft(2, '0')}/'
            '${date.month.toString().padLeft(2, '0')}/'
            '${date.year}';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: _muted, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              formatted,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: date == null ? _muted : _ink,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _evidenceCard() {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _uploadDone ? _success.withValues(alpha: 0.5) : _border,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_uploading)
            const Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text('Uploading…', style: TextStyle(fontSize: 14, color: _muted)),
              ],
            )
          else if (_uploadDone && _evidenceFileName != null)
            Row(
              children: [
                const Icon(Icons.check_circle, color: _success, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _evidenceFileName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: _success,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _pickAndUploadEvidence,
                  child: const Text('Change'),
                ),
              ],
            )
          else
            Row(
              children: [
                const Icon(Icons.upload_file_outlined, color: _muted, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Upload a PDF, DOCX, or image (optional)',
                    style: const TextStyle(fontSize: 13, color: _muted),
                  ),
                ),
                OutlinedButton(
                  onPressed: _pickAndUploadEvidence,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _accent,
                    side: BorderSide(color: _accent.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Choose file'),
                ),
              ],
            ),
          if (_evidenceError != null) ...[
            const SizedBox(height: 8),
            Text(
              _evidenceError!,
              style: const TextStyle(fontSize: 12, color: Color(0xFFB91C1C)),
            ),
          ],
        ],
      ),
    );
  }
}
