// lib/features/zancrew/onboarding/uk_work_status_screen.dart
import 'package:flutter/material.dart';
import 'uk_apply_screen.dart';

class UkWorkStatusScreen extends StatelessWidget {
  const UkWorkStatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Right to Work in the UK'),
        backgroundColor: Colors.orangeAccent,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'What is your UK work status?',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'We are legally required to verify your right to work in the UK before you can earn as an independent provider.',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 28),
              _StatusTile(
                title: 'British / Irish citizen',
                subtitle: 'UK or Irish passport holder',
                value: 'british_irish',
                requiresShareCode: false,
              ),
              _StatusTile(
                title: 'EU Settled or Pre-Settled Status',
                subtitle: 'EUSS granted — provide GOV.UK share code',
                value: 'settled_pre_settled',
                requiresShareCode: true,
              ),
              _StatusTile(
                title: 'Graduate Visa',
                subtitle: 'Post-study work visa — provide GOV.UK share code',
                value: 'graduate_visa',
                requiresShareCode: true,
              ),
              _StatusTile(
                title: 'Skilled Worker / restricted work visa',
                subtitle: 'Provide GOV.UK share code for right to work',
                value: 'skilled_worker_or_other',
                requiresShareCode: true,
              ),
              _StatusTile(
                title: 'Student Visa',
                subtitle: 'Share your details — we\'ll keep them ready for when a student route launches.',
                value: 'student_visa',
                requiresShareCode: true,
              ),
              _StatusTile(
                title: 'Other visa / I\'m not sure',
                subtitle: 'Choose this if you need help proving your right to work.',
                value: 'unknown',
                requiresShareCode: false,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final String value;
  final bool requiresShareCode;

  const _StatusTile({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.requiresShareCode,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right, color: Colors.orange),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => UkApplyScreen(
              workStatus: value,
              requiresShareCode: requiresShareCode,
            ),
          ),
        ),
      ),
    );
  }
}

