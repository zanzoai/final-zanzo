// -----------------------------------------------------------------------------
// ZanCrew Onboarding — WELCOME SCREEN
//
// Purpose of this screen:
//  1) Introduce ZanCrew earning mode to new users
//  2) Explain benefits (flexible work, nearby tasks, instant payouts)
//  3) Entry point into the onboarding process
//  4) User choices:
//        - “Start” → Begin phone verification flow
//        - “Maybe later” → Exit onboarding
//
// Navigation:
//   Start        → ZanCrewPhoneCheckScreen()
//   Maybe later → Navigator.pop(context)
//
// File: lib/features/zancrew/onboarding/welcome_screen.dart
// -----------------------------------------------------------------------------

import 'package:flutter/material.dart';
import 'phone_check_screen.dart';

class ZanCrewWelcomeScreen extends StatelessWidget {
  const ZanCrewWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 40),

              // ---------------------------------------------------------------
              // Title
              // ---------------------------------------------------------------
              const Text(
                "Earn with Zanzo",
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 12),

              // ---------------------------------------------------------------
              // Subtitle
              // ---------------------------------------------------------------
              const Text(
                "Get paid to help people nearby with real-world tasks.\n"
                "Flexible hours. Instant payouts. No boss.",
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.black54,
                ),
                textAlign: TextAlign.center,
              ),

              const Spacer(),

              // ---------------------------------------------------------------
              // START BUTTON
              // ---------------------------------------------------------------
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const ZanCrewPhoneCheckScreen(),
                      ),
                    );
                  },
                  child: const Text(
                    "Start",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 18),

              // ---------------------------------------------------------------
              // MAYBE LATER
              // ---------------------------------------------------------------
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  "Maybe later",
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 14,
                  ),
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}