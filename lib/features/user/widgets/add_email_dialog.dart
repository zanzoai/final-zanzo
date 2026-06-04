// This dialog allows the user to add or update their email address.
// Validates format → sends API request → updates SharedPreferences.

// lib/features/user/widgets/add_email_dialog.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zanzo_frontend/core/services/api_service.dart';

/// Opens the Add/Update Email dialog.
/// Returns `true` if saved successfully, otherwise `false`.
Future<bool> showAddEmailDialog(
  BuildContext context, {
  String? current,
}) async {
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

  bool _sending = false;
  String? _error;

  // ---------------------------------------------------------------------------
  // INIT + DISPOSE
  // ---------------------------------------------------------------------------

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
  // HELPERS
  // ---------------------------------------------------------------------------

  bool _isValidEmail(String value) {
    final emailRegex = RegExp(r'^[\w\.\-]+@([\w\-]+\.)+[a-zA-Z]{2,}$');
    return emailRegex.hasMatch(value.trim());
  }

  Future<void> _save() async {
    setState(() {
      _sending = true;
      _error = null;
    });

    final email = _emailCtrl.text.trim();

    if (!_isValidEmail(email)) {
      setState(() {
        _sending = false;
        _error = 'Enter a valid email address.';
      });
      return;
    }

    try {
      final ok = await ApiService.updateEmail(email);
      if (!mounted) return;

      if (ok) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_email', email);
        Navigator.of(context).pop(true);
      } else {
        setState(() => _error = 'Server rejected email.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Network error: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.currentEmail == null ? 'Add Email' : 'Update Email',
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(color: Colors.red),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _sending ? null : _save,
          child: _sending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}