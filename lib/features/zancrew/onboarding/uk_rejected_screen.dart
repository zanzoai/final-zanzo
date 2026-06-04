// lib/features/zancrew/onboarding/uk_rejected_screen.dart
import 'package:flutter/material.dart';

class UkRejectedScreen extends StatelessWidget {
  final String status; // 'rejected' or 'suspended'
  final String? reason;

  const UkRejectedScreen({
    super.key,
    required this.status,
    this.reason,
  });

  @override
  Widget build(BuildContext context) {
    final isSuspended = status == 'suspended';

    return Scaffold(
      appBar: AppBar(
        title: Text(isSuspended ? 'Account Suspended' : 'Application Not Approved'),
        backgroundColor: Colors.red,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isSuspended ? Icons.pause_circle_filled : Icons.cancel,
                size: 72,
                color: Colors.red.shade400,
              ),
              const SizedBox(height: 24),
              Text(
                isSuspended ? 'Provider Access Suspended' : 'Application Not Approved',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                isSuspended
                    ? 'Your provider access has been suspended. Please contact support for more information.'
                    : 'Unfortunately your provider application was not approved at this time.',
                style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
                textAlign: TextAlign.center,
              ),
              if (reason != null && reason!.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Text(
                    reason!,
                    style: TextStyle(fontSize: 13, color: Colors.red.shade900),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              const SizedBox(height: 40),
              OutlinedButton(
                onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
                child: const Text('Back to Home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
