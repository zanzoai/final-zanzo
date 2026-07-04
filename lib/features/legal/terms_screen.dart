// lib/features/legal/terms_screen.dart

import 'package:flutter/material.dart';
import 'legal_scaffold.dart';

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  static const routeName = '/terms';

  @override
  Widget build(BuildContext context) {
    return const LegalScaffold(
      title: 'Terms & Conditions',
      lastUpdated: 'July 2025',
      sections: [
        LegalSection(
          icon: Icons.info_outline,
          title: 'About This App',
          child: Text(
            'Zanzo is currently operating as a pilot/testing version. Features, '
            'pricing, and policies may change as we develop the product. By using '
            'the app you accept these terms in their current form. We will notify '
            'you of significant changes before they take effect.',
            style: legalBodyStyle,
          ),
        ),
        LegalSection(
          icon: Icons.people_outline,
          title: 'How the Platform Works',
          child: Text(
            'Zanzo connects customers who need simple, safe, non-skilled local '
            'help with approved assistants called ZanCrew. Customers submit task '
            'requests through the app. Nearby ZanCrew may accept and complete '
            'those tasks. Zanzo provides the platform and does not guarantee '
            'task availability, completion speed, or outcome.',
            style: legalBodyStyle,
          ),
        ),
        LegalSection(
          icon: Icons.person_outline,
          title: 'Your Account',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You must provide accurate, up-to-date information including '
                'your phone number, name, and location. You must be 18 or older '
                'to use Zanzo. You are responsible for:',
                style: legalBodyStyle,
              ),
              SizedBox(height: 8),
              LegalBullet('Keeping your account details accurate'),
              LegalBullet('Keeping your account secure and not sharing access'),
              LegalBullet('All activity that occurs under your account'),
            ],
          ),
        ),
        LegalSection(
          icon: Icons.check_circle_outline,
          title: 'Acceptable Tasks',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Customers may request simple, safe, non-skilled help. Examples '
                'include:',
                style: legalBodyStyle,
              ),
              SizedBox(height: 8),
              LegalBullet(
                'Waiting or being present for a delivery or appointment',
              ),
              LegalBullet('Simple queue or wait tasks'),
              LegalBullet('Light cleaning or room organising'),
              LegalBullet('Light packing or suitcase help'),
              LegalBullet(
                'Simple event setup such as balloons or table arrangement',
              ),
              LegalBullet(
                'Prepaid pickup and drop-off of non-restricted items',
              ),
              LegalBullet('Simple local assistance at a specified location'),
              SizedBox(height: 8),
              Text(
                'ZanCrew must only accept tasks they can safely and lawfully '
                'complete.',
                style: legalBodyStyle,
              ),
            ],
          ),
        ),
        LegalSection(
          icon: Icons.block,
          title: 'Prohibited Requests & Conduct',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You must not request, accept, or facilitate tasks involving:',
                style: legalBodyStyle,
              ),
              SizedBox(height: 8),
              LegalBullet(
                'Purchasing items using ZanCrew\'s own money or any form of '
                'reimbursement-later arrangement',
              ),
              LegalBullet('Cash handling, money transfer, or bank visits'),
              LegalBullet(
                'Alcohol, tobacco, vapes, drugs, or controlled substances',
              ),
              LegalBullet('Medicines, prescriptions, or pharmacy collections'),
              LegalBullet(
                'Adult, sexual, escort, intimate, or massage-type services',
              ),
              LegalBullet(
                'Childcare, elderly care, personal care, or medical assistance',
              ),
              LegalBullet(
                'Regulated trade work including electrical, gas, plumbing, or '
                'locksmith services',
              ),
              LegalBullet(
                'Appliance, car, broadband, or specialist repair work',
              ),
              LegalBullet(
                'Pest control, chemical use, power tools, ladders, roofs, or '
                'physically dangerous work',
              ),
              LegalBullet('Passenger transport or driving people'),
              LegalBullet(
                'Any illegal, fraudulent, threatening, abusive, discriminatory, '
                'or stalking-related activity',
              ),
              SizedBox(height: 8),
              Text(
                'You must not harass, threaten, stalk, or endanger any other '
                'user or third party. Zanzo may suspend or permanently remove '
                'accounts for misuse.',
                style: legalBodyStyle,
              ),
            ],
          ),
        ),
        LegalSection(
          icon: Icons.payment_outlined,
          title: 'Payments, Cancellations & Disputes',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LegalBullet(
                'Payments are processed securely through the app where available.',
              ),
              LegalBullet(
                'ZanCrew must not pay anything upfront using their own money.',
              ),
              LegalBullet(
                'Cancellations and refunds depend on timing and circumstances '
                'at the point of cancellation.',
              ),
              LegalBullet(
                'Disputes are handled through Zanzo support and admin review.',
              ),
              LegalBullet(
                'Zanzo reserves the right to cancel or reject tasks for safety, '
                'legal, fraud, or policy reasons.',
              ),
            ],
          ),
        ),
        LegalSection(
          icon: Icons.warning_amber_outlined,
          title: 'Our Limitations',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Zanzo is not an emergency service. If someone is in danger, '
                'contact emergency services (999) immediately.',
                style: legalBodyStyle,
              ),
              SizedBox(height: 8),
              Text(
                'Zanzo is a platform service, not a medical, care, transport, '
                'financial, or regulated trades provider. ZanCrew are independent '
                'and are not employed by Zanzo. We take reasonable steps to '
                'maintain platform safety, but we cannot guarantee the conduct, '
                'skill, or reliability of ZanCrew.',
                style: legalBodyStyle,
              ),
              SizedBox(height: 8),
              Text(
                'Nothing in these terms limits our liability for death or '
                'personal injury caused by our negligence, for fraud, or for '
                'any other liability that cannot lawfully be excluded.',
                style: legalBodyStyle,
              ),
            ],
          ),
        ),
        LegalSection(
          icon: Icons.edit_note_outlined,
          title: 'Changes to Terms',
          child: Text(
            'These terms may be updated as Zanzo develops. We will notify you '
            'of significant changes before they take effect. Continued use of '
            'the app after notification means you accept the updated terms.',
            style: legalBodyStyle,
          ),
        ),
      ],
    );
  }
}
