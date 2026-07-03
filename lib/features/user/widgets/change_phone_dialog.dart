// Collects a new phone number and sends an OTP to it.
// Returns: the new phone string if OTP was sent, null if cancelled.
//
// lib/features/user/widgets/change_phone_dialog.dart

import 'package:flutter/material.dart';
import 'package:zanzo_frontend/core/services/api_service.dart';

// Zanzo palette (mirrors login / email dialog)
const _kSaffron = Color(0xFFD97706);
const _kInk = Color(0xFF26211C);
const _kMuted = Color(0xFF8C8378);
const _kBg = Color(0xFFFCFAF6);
const _kLine = Color(0xFFE8E2D9);

Future<String?> showChangePhoneDialog(
  BuildContext context, {
  required String? currentPhone,
}) {
  final controller = TextEditingController(text: currentPhone ?? '');
  bool loading = false;
  String? error;

  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          return Dialog(
            backgroundColor: _kBg,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 28,
              vertical: 24,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Title
                  const Text(
                    'Update phone',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: _kInk,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  // Subtitle
                  const Text(
                    'Change the phone number linked to your account.',
                    style: TextStyle(
                      fontSize: 13,
                      color: _kMuted,
                      fontWeight: FontWeight.w400,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Phone field
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.done,
                    autofocus: true,
                    maxLength: 15,
                    onSubmitted: (_) {
                      if (!loading) {
                        _submit(
                          ctx,
                          controller,
                          setState,
                          (v) {
                            loading = v;
                            error = null;
                          },
                          (e) {
                            error = e;
                          },
                        );
                      }
                    },
                    decoration: InputDecoration(
                      labelText: 'New phone number',
                      hintText: '+447700123456',
                      counterText: '',
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
                        borderSide: const BorderSide(
                          color: _kSaffron,
                          width: 1.5,
                        ),
                      ),
                    ),
                  ),

                  // Error
                  if (error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      error!,
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
                        onPressed: loading
                            ? null
                            : () => Navigator.pop(ctx, null),
                        style: TextButton.styleFrom(foregroundColor: _kMuted),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 44,
                        child: ElevatedButton(
                          onPressed: loading
                              ? null
                              : () => _submit(ctx, controller, setState, (v) {
                                  loading = v;
                                  error = null;
                                }, (e) => error = e),
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
                          child: loading
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Next'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

// Extracted to avoid duplicating the submit logic between onSubmitted and button.
Future<void> _submit(
  BuildContext ctx,
  TextEditingController controller,
  StateSetter setState,
  void Function(bool) setLoading,
  void Function(String) setError,
) async {
  final raw = controller.text.trim();

  final valid = RegExp(r'^\+?[0-9]{10,15}$').hasMatch(raw);
  if (!valid) {
    setState(
      () => setError('Enter a valid phone number (e.g. +447700123456).'),
    );
    return;
  }

  setState(() => setLoading(true));
  try {
    final res = await ApiService.sendUpdatePhoneOtp(raw);
    if (res.statusCode == 200) {
      if (ctx.mounted) Navigator.pop(ctx, raw);
    } else {
      setState(() => setError('Failed to send code. Please try again.'));
    }
  } catch (e) {
    setState(() => setError('Network error: $e'));
  } finally {
    setState(() => setLoading(false));
  }
}
