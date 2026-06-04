// This file shows an OTP dialog used when a user updates their phone number,
// sends the OTP to backend for verification, and returns true/false.

// lib/core/widgets/verify_phone_otp_dialog.dart

import 'package:flutter/material.dart';
import 'package:zanzo_frontend/core/services/api_service.dart';

// ---------------------------------------------------------------------------
// 1) SHOW OTP DIALOG (UI + INPUT)
// ---------------------------------------------------------------------------
Future<bool?> showVerifyPhoneOtpDialog(
  BuildContext context, {
  required String newPhone,
}) {
  final controller = TextEditingController();
  bool loading = false;

  return showDialog<bool>(
    context: context,
    barrierDismissible: !loading,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            title: const Text("Verify OTP"),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text("We sent an OTP to $newPhone"),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    hintText: "Enter OTP",
                    counterText: "",
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),

            // -----------------------------------------------------------------
            // 2) BUTTONS → CANCEL OR VERIFY
            // -----------------------------------------------------------------
            actions: [
              TextButton(
                onPressed: loading ? null : () => Navigator.pop(ctx, false),
                child: const Text("Cancel"),
              ),
              ElevatedButton(
                onPressed: loading
                    ? null
                    : () async {
                        final code = controller.text.trim();

                        if (code.length != 6) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("❌ Enter valid 6-digit OTP"),
                            ),
                          );
                          return;
                        }

                        setState(() => loading = true);

                        try {
                          final res = await ApiService.verifyUpdatePhoneOtp(
                            newPhone,
                            code,
                          );

                          if (res.statusCode == 200) {
                            Navigator.pop(ctx, true); // success
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text("❌ Failed: ${res.body}")),
                            );
                          }
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text("❌ Error: $e")),
                          );
                        } finally {
                          setState(() => loading = false);
                        }
                      },
                child: loading
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text("Verify"),
              ),
            ],
          );
        },
      );
    },
  );
}