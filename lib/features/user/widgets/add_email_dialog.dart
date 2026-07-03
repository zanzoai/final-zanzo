// lib/features/user/widgets/add_email_dialog.dart
// Add / update email dialog — matches Zanzo sign-in dialog style.

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zanzo_frontend/core/services/api_service.dart';

// Zanzo palette (mirrors login_prompt_dialog.dart)
const _kSaffron = Color(0xFFD97706);
const _kInk = Color(0xFF26211C);
const _kMuted = Color(0xFF8C8378);
const _kBg = Color(0xFFFCFAF6);
const _kLine = Color(0xFFE8E2D9);

/// Opens the Add / Update Email dialog.
/// Returns `true` if the email was saved successfully, `false` otherwise.
Future<bool> showAddEmailDialog(BuildContext context, {String? current}) async {
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _AddEmailDialog(currentEmail: current),
      ) ??
      false;
}

class _AddEmailDialog extends StatefulWidget {
  final String? currentEmail;

  const _AddEmailDialog({this.currentEmail});

  @override
  State<_AddEmailDialog> createState() => _AddEmailDialogState();
}

class _AddEmailDialogState extends State<_AddEmailDialog> {
  final _emailCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.currentEmail != null) {
      _emailCtrl.text = widget.currentEmail!;
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------

  bool _isValidEmail(String v) =>
      RegExp(r'^[\w.\-]+@([\w\-]+\.)+[a-zA-Z]{2,}$').hasMatch(v.trim());

  Future<void> _save() async {
    final email = _emailCtrl.text.trim();

    if (email.isEmpty) {
      setState(() => _error = 'Enter your email address.');
      return;
    }
    if (!_isValidEmail(email)) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final ok = await ApiService.updateEmail(email);
      if (!mounted) return;

      if (ok) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_email', email);
        if (!mounted) return;
        Navigator.of(context).pop(true);
      } else {
        setState(() => _error = 'Could not save email. Please try again.');
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Network error: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isUpdate = widget.currentEmail != null;

    return Dialog(
      backgroundColor: _kBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title
            Text(
              isUpdate ? 'Update email' : 'Add email',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: _kInk,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            // Subtitle
            Text(
              isUpdate
                  ? 'Change the email linked to your account.'
                  : 'Add an email for receipts and account recovery.',
              style: const TextStyle(
                fontSize: 13,
                color: _kMuted,
                fontWeight: FontWeight.w400,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),

            // Email field
            TextField(
              controller: _emailCtrl,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.email],
              autofocus: true,
              onSubmitted: (_) => _saving ? null : _save(),
              decoration: InputDecoration(
                labelText: 'Email address',
                hintText: 'you@example.com',
                labelStyle: const TextStyle(color: _kMuted, fontSize: 14),
                hintStyle: TextStyle(
                  color: _kLine.withValues(alpha: 0.8),
                  fontSize: 14,
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _kLine),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _kSaffron, width: 1.5),
                ),
              ),
            ),

            // Error
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(
                  color: Color(0xFFDC2626),
                  fontSize: 13,
                  height: 1.3,
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: _saving
                      ? null
                      : () => Navigator.of(context).pop(false),
                  style: TextButton.styleFrom(foregroundColor: _kMuted),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 44,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kSaffron,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: _kLine,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
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
                        : const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
