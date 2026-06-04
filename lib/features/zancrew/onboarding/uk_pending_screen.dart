// lib/features/zancrew/onboarding/uk_pending_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/uk_provider_api.dart';
import '../dashboard/zancrew_dashboard.dart';
import 'uk_rejected_screen.dart';

class UkPendingScreen extends StatefulWidget {
  const UkPendingScreen({super.key});

  @override
  State<UkPendingScreen> createState() => _UkPendingScreenState();
}

class _UkPendingScreenState extends State<UkPendingScreen> {
  Timer? _pollTimer;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    // Poll every 30 seconds while the screen is open
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => _checkStatus());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkStatus() async {
    if (_checking) return;
    setState(() => _checking = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString('user_id');
      if (userId == null || !mounted) return;

      final result = await UkProviderApi.getStatus(userId);
      if (result == null || !mounted) return;

      final providerStatus = result['provider_status'] as String? ?? 'pending';
      final canReceive = result['can_receive_offers'] == true;

      if (providerStatus == 'approved' && canReceive) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const ZanCrewDashboard()),
        );
      } else if (providerStatus == 'rejected' || providerStatus == 'suspended') {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => UkRejectedScreen(
              status: providerStatus,
              reason: result['rejection_reason'] as String?,
            ),
          ),
        );
      }
    } catch (_) {
      // ignore transient poll errors
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Application Pending'),
        backgroundColor: Colors.orangeAccent,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.hourglass_top, size: 72, color: Colors.orange),
              const SizedBox(height: 24),
              const Text(
                'Application Under Review',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Text(
                'Your application has been submitted and is being reviewed by our team.\n\nThis usually takes 1–2 working days. You will be able to receive job offers once approved.',
                style: TextStyle(fontSize: 15, color: Colors.grey.shade700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _checking ? null : _checkStatus,
                icon: _checking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.refresh),
                label: const Text('Check Status'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent,
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
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
