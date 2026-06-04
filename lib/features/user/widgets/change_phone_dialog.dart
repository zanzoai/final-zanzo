// This dialog collects a new phone number and sends an OTP to it.
// Caller will handle OTP verification separately.
// Returns: the new phone (String) if OTP was sent successfully, else null.
//
// lib/features/user/widgets/change_phone_dialog.dart

import 'package:flutter/material.dart';
import 'package:zanzo_frontend/core/services/api_service.dart';

Future<String?> showChangePhoneDialog(
  BuildContext context, {
  required String? currentPhone,
}) {
  final controller = TextEditingController(text: currentPhone ?? "");
  bool loading = false;

  return showDialog<String>(
    context: context,
    barrierDismissible: !loading,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (ctx, setState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),

            // ---------------------------------------------------------------------------
            // TITLE
            // ---------------------------------------------------------------------------
            title: const Text("Update Phone"),

            // ---------------------------------------------------------------------------
            // CONTENT → ENTER NEW PHONE NUMBER
            // ---------------------------------------------------------------------------
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Enter your new phone number:"),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.phone,
                  maxLength: 15,
                  decoration: const InputDecoration(
                    hintText: "+919876543210",
                    counterText: "",
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  "Only digits and + allowed. Example: +447912345678",
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ],
            ),

            // ---------------------------------------------------------------------------
            // ACTION BUTTONS
            // ---------------------------------------------------------------------------
            actions: [
              // CANCEL
              TextButton(
                onPressed: loading ? null : () => Navigator.pop(ctx, null),
                child: const Text("Cancel"),
              ),

              // NEXT (SEND OTP)
              ElevatedButton(
                onPressed: loading
                    ? null
                    : () async {
                        final raw = controller.text.trim();

                        // Validate phone format
                        final valid = RegExp(
                          r'^\+?[0-9]{10,15}$',
                        ).hasMatch(raw);
                        if (!valid) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("❌ Invalid phone format"),
                            ),
                          );
                          return;
                        }

                        setState(() => loading = true);

                        try {
                          // ---------------------------------------------------------------------------
                          // SEND OTP (ONLY SEND HERE → no verification)
                          // ---------------------------------------------------------------------------
                          final res = await ApiService.sendUpdatePhoneOtp(raw);

                          if (res.statusCode == 200) {
                            Navigator.pop(ctx, raw); // return phone to caller
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
                    : const Text("Next"),
              ),
            ],
          );
        },
      );
    },
  );
}
