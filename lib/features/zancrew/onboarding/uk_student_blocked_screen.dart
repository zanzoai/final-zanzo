// lib/features/zancrew/onboarding/uk_student_blocked_screen.dart
import 'package:flutter/material.dart';

class UkStudentBlockedScreen extends StatelessWidget {
  const UkStudentBlockedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Not Eligible'),
        backgroundColor: Colors.red,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.block, size: 72, color: Colors.red.shade400),
              const SizedBox(height: 24),
              const Text(
                'Student Visa — Not Eligible',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Student visa holders are not permitted to earn as independent providers in the UK MVP.\n\nYou may still use Zanzo as a customer.',
                style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
                textAlign: TextAlign.center,
              ),
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
