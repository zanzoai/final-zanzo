// lib/features/legal/privacy_screen.dart

import 'package:flutter/material.dart';
import 'legal_scaffold.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static const routeName = '/privacy';

  @override
  Widget build(BuildContext context) {
    return const LegalScaffold(
      title: 'Privacy Policy',
      lastUpdated: 'July 2025',
      sections: [
        LegalSection(
          icon: Icons.business_outlined,
          title: 'Who We Are',
          child: Text(
            'Zanzo AI Ltd is responsible for this app and how your personal '
            'data is handled. If you have questions about your data, please '
            'contact us through support in the app.',
            style: legalBodyStyle,
          ),
        ),
        LegalSection(
          icon: Icons.storage_outlined,
          title: 'Data We Collect',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'When you use Zanzo, we may collect:',
                style: legalBodyStyle,
              ),
              SizedBox(height: 8),
              LegalBullet(
                'Phone number — required for account login and verification',
              ),
              LegalBullet(
                'Name or display name — used to personalise your experience',
              ),
              LegalBullet(
                'Email address — optional; used for receipts and account recovery',
              ),
              LegalBullet(
                'Location and address information — used for task matching '
                'and progress tracking',
              ),
              LegalBullet(
                'Task request details, status, and history — needed to manage tasks',
              ),
              LegalBullet(
                'Payment references and status — we do not store full card '
                'details; payments are handled by our payment provider',
              ),
              LegalBullet(
                'Device tokens — used to send push notifications you have enabled',
              ),
              LegalBullet(
                'Support messages and admin notes — used for dispute resolution '
                'and safety',
              ),
              LegalBullet(
                'Basic technical and app usage data — used to improve the app '
                'during its pilot phase',
              ),
            ],
          ),
        ),
        LegalSection(
          icon: Icons.tune_outlined,
          title: 'How We Use It',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('We use your data to:', style: legalBodyStyle),
              SizedBox(height: 8),
              LegalBullet('Create and manage your account'),
              LegalBullet('Verify your phone number and identity'),
              LegalBullet('Create, match, and manage task requests'),
              LegalBullet('Connect customers with nearby available ZanCrew'),
              LegalBullet('Show real-time task progress and status updates'),
              LegalBullet(
                'Maintain safety, prevent fraud, and enforce our rules',
              ),
              LegalBullet(
                'Process and track payments through our payment provider',
              ),
              LegalBullet('Handle support queries and dispute resolution'),
              LegalBullet(
                'Send push notifications you have enabled on your device',
              ),
              LegalBullet(
                'Improve the app and understand how it is being used',
              ),
            ],
          ),
        ),
        LegalSection(
          icon: Icons.share_outlined,
          title: 'Who We Share It With',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'We may share your data with trusted third parties only '
                'where necessary:',
                style: legalBodyStyle,
              ),
              SizedBox(height: 8),
              LegalBullet(
                'Payment provider — to process and manage transactions',
              ),
              LegalBullet(
                'Maps and location services — to display task locations and '
                'routing information',
              ),
              LegalBullet(
                'Push notification services — to deliver app notifications '
                'to your device',
              ),
              LegalBullet(
                'Support and admin tools — to assist with queries, disputes, '
                'and safety reviews',
              ),
              LegalBullet(
                'Legal or regulatory authorities — where required by law '
                'or to protect the safety of users',
              ),
              SizedBox(height: 8),
              Text(
                'We do not sell your personal data.',
                style: TextStyle(
                  fontSize: 13.5,
                  color: Color(0xFF26211C),
                  height: 1.6,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        LegalSection(
          icon: Icons.location_on_outlined,
          title: 'Location Data',
          child: Text(
            'Location information is used to match your task with nearby '
            'ZanCrew and to track task progress. We do not use your location '
            'data for unrelated advertising, profiling, or background tracking '
            'outside of active task use.',
            style: legalBodyStyle,
          ),
        ),
        LegalSection(
          icon: Icons.verified_user_outlined,
          title: 'Your Rights',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('You can contact us at any time to:', style: legalBodyStyle),
              SizedBox(height: 8),
              LegalBullet('Ask what personal data we hold about you'),
              LegalBullet('Request corrections to inaccurate data'),
              LegalBullet('Request deletion of your data where applicable'),
              LegalBullet(
                'Object to or restrict how we process your data in certain '
                'circumstances',
              ),
              SizedBox(height: 8),
              Text(
                'We will respond as promptly as reasonably possible. Some data '
                'may need to be retained for legal, safety, or legitimate '
                'business reasons even after a deletion request.',
                style: legalBodyStyle,
              ),
            ],
          ),
        ),
        LegalSection(
          icon: Icons.schedule_outlined,
          title: 'Data Retention',
          child: Text(
            'We keep your data only as long as reasonably needed for your '
            'account, task records, safety purposes, legal obligations, and '
            'legitimate business purposes. Accounts that have been inactive '
            'for an extended period may be removed in line with our internal '
            'data retention policy.',
            style: legalBodyStyle,
          ),
        ),
        LegalSection(
          icon: Icons.edit_note_outlined,
          title: 'Updates to This Policy',
          child: Text(
            'This Privacy Policy may be updated as Zanzo develops. We will '
            'notify you of significant changes through the app. Continued '
            'use of the app after notification means you accept the updated '
            'policy.',
            style: legalBodyStyle,
          ),
        ),
      ],
    );
  }
}
