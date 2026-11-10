// lib/features/user/widgets/support_sheet.dart
//
// Public bottom-sheet widget for raising/viewing task support requests.
// Extracted from track_job_screen.dart so completed and cancelled booking
// screens can reuse it without importing the whole track screen.

import 'package:flutter/material.dart';
import 'package:zanzo_frontend/core/services/api_service.dart';
import 'package:zanzo_frontend/core/theme/app_theme.dart';

/// Opens a modal bottom-sheet with the Zanzo Support form for [taskId].
///
/// Convenience wrapper — callers typically prefer this over constructing
/// [SupportSheet] manually:
///
/// ```dart
/// openSupportSheet(context, taskId: job['id']);
/// ```
void openSupportSheet(BuildContext context, {required String taskId}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => SupportSheet(taskId: taskId),
  );
}

class SupportSheet extends StatefulWidget {
  final String taskId;
  const SupportSheet({super.key, required this.taskId});

  @override
  State<SupportSheet> createState() => _SupportSheetState();
}

class _SupportSheetState extends State<SupportSheet> {
  static const Color _accent = AppColors.saffron;
  static const Color _ink = AppColors.ink;
  static const Color _muted = AppColors.muted;
  static const Color _border = AppColors.divider;
  static const Color _surface = AppColors.surfaceMuted;

  static const List<String> _chips = [
    'Crew late',
    'Task issue',
    'Payment',
    'Safety',
    'Other',
  ];

  String? _selectedChip;
  final _messageCtrl = TextEditingController();
  bool _sending = false;
  List<Map<String, dynamic>> _requests = [];
  bool _loadingRequests = false;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRequests() async {
    setState(() => _loadingRequests = true);
    try {
      final list = await ApiService.getSupportRequestsForTask(widget.taskId);
      if (mounted) setState(() => _requests = list);
    } catch (_) {
      // silent — compose form still shown
    } finally {
      if (mounted) setState(() => _loadingRequests = false);
    }
  }

  bool get _canSend => _messageCtrl.text.trim().isNotEmpty && !_sending;

  Future<void> _send() async {
    final msg = _messageCtrl.text.trim();
    if (msg.isEmpty || _sending) return;
    setState(() => _sending = true);
    var success = false;
    try {
      await ApiService.createSupportRequest(
        widget.taskId,
        subject: _selectedChip,
        message: msg,
      );
      success = true;
      if (!mounted) return;
      _messageCtrl.clear();
      setState(() => _selectedChip = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks — our team will review this.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Something went wrong. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    if (success && mounted) await _loadRequests();
  }

  Widget _statusBadge(String status) {
    final String label;
    final Color bg;
    final Color fg;
    switch (status) {
      case 'open':
        label = 'Open';
        bg = const Color(0xFFFEF3C7);
        fg = _accent;
        break;
      case 'in_progress':
        label = 'In progress';
        bg = const Color(0xFFDBEAFE);
        fg = const Color(0xFF1D4ED8);
        break;
      case 'resolved':
        label = 'Resolved';
        bg = const Color(0xFFDCFCE7);
        fg = const Color(0xFF16A34A);
        break;
      default:
        label = status;
        bg = _surface;
        fg = _muted;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }

  Widget _buildHistory() {
    if (_loadingRequests) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_requests.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        for (final req in _requests)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (req['subject'] != null &&
                        (req['subject'] as String).isNotEmpty) ...[
                      Text(
                        req['subject'] as String,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    _statusBadge((req['status'] as String?) ?? 'open'),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  (req['message'] as String?) ?? '',
                  style: const TextStyle(fontSize: 13.5, color: _ink),
                ),
                const SizedBox(height: 10),
                if (req['admin_response'] != null &&
                    (req['admin_response'] as String).isNotEmpty) ...[
                  const Text(
                    'Our team replied',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: _accent,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    req['admin_response'] as String,
                    style: const TextStyle(fontSize: 13.5, color: _ink),
                  ),
                ] else
                  const Text(
                    'Support has received your request. Our team will review this.',
                    style: TextStyle(fontSize: 13, color: _muted),
                  ),
              ],
            ),
          ),
        const Divider(height: 28),
        const Text(
          'Send another request',
          style: TextStyle(fontSize: 13.5, color: _muted),
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(20, 0, 20, bottom + 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 18),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),

              const Text(
                'Need help?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: _ink,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Support for this task',
                style: TextStyle(fontSize: 13.5, color: _muted),
              ),
              const SizedBox(height: 18),

              // History
              _buildHistory(),

              // Category chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _chips.map((chip) {
                  final selected = _selectedChip == chip;
                  return GestureDetector(
                    onTap: () =>
                        setState(() => _selectedChip = selected ? null : chip),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: selected ? const Color(0xFFFEF3C7) : _surface,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: selected ? _accent : _border,
                          width: selected ? 1.5 : 1.0,
                        ),
                      ),
                      child: Text(
                        chip,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: selected ? _accent : _ink,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Message field
              TextField(
                controller: _messageCtrl,
                onChanged: (_) => setState(() {}),
                maxLines: 4,
                maxLength: 4000,
                decoration: InputDecoration(
                  hintText: 'Tell us what happened…',
                  hintStyle: const TextStyle(color: _muted),
                  counterText: '',
                  filled: true,
                  fillColor: _surface,
                  contentPadding: const EdgeInsets.all(14),
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
                    borderSide: const BorderSide(color: _ink, width: 1.5),
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(
                      Icons.keyboard_hide_rounded,
                      color: _muted,
                      size: 20,
                    ),
                    onPressed: () => FocusScope.of(context).unfocus(),
                    tooltip: 'Dismiss keyboard',
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Send button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _canSend ? _send : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    disabledBackgroundColor: _border,
                    disabledForegroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          'Send to support',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15.5,
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
