// lib/features/legal/task_rules_screen.dart

import 'package:flutter/material.dart';
import 'legal_scaffold.dart';

class TaskRulesScreen extends StatelessWidget {
  const TaskRulesScreen({super.key});

  static const routeName = '/task_rules';

  @override
  Widget build(BuildContext context) {
    return const LegalScaffold(
      title: 'Task Rules & Safety',
      lastUpdated: 'July 2025',
      sections: [
        LegalSection(
          icon: Icons.check_circle_outline,
          title: 'What ZanCrew Can Help With',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Zanzo is designed for simple, safe, non-skilled local help. '
                'Examples of acceptable tasks include:',
                style: legalBodyStyle,
              ),
              SizedBox(height: 8),
              LegalBullet(
                'Waiting or being present for a delivery or appointment',
              ),
              LegalBullet('Simple queue or wait tasks at a location'),
              LegalBullet('Light cleaning or tidying'),
              LegalBullet('Room organising or rearranging'),
              LegalBullet('Light packing or suitcase help'),
              LegalBullet(
                'Simple event setup — such as arranging balloons or tables',
              ),
              LegalBullet(
                'Light garden tidying without tools, chemicals, ladders, or '
                'heavy lifting',
              ),
              LegalBullet(
                'Prepaid collection and drop-off of non-restricted items',
              ),
              LegalBullet('Simple local assistance at a specified location'),
            ],
          ),
        ),
        LegalSection(
          icon: Icons.money_off_outlined,
          title: 'Not Allowed — Purchases & Money',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ZanCrew must never use their own money for a task. The '
                'following are strictly not allowed:',
                style: legalBodyStyle,
              ),
              SizedBox(height: 8),
              LegalBullet('Buying items using ZanCrew\'s own money'),
              LegalBullet(
                'Reimbursement-later or "buy and I\'ll pay you back" tasks',
              ),
              LegalBullet(
                'Cash handling or collecting money on behalf of anyone',
              ),
              LegalBullet('Bank deposits, withdrawals, or money transfers'),
            ],
          ),
        ),
        LegalSection(
          icon: Icons.no_drinks_outlined,
          title: 'Not Allowed — Regulated & Restricted Items',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tasks must not involve the collection, handling, or delivery of:',
                style: legalBodyStyle,
              ),
              SizedBox(height: 8),
              LegalBullet('Alcohol'),
              LegalBullet('Tobacco or cigarettes'),
              LegalBullet('Vapes or e-cigarettes'),
              LegalBullet('Drugs or controlled substances'),
              LegalBullet('Medicines or prescription drugs'),
              LegalBullet('Pharmacy collections of any kind'),
            ],
          ),
        ),
        LegalSection(
          icon: Icons.block,
          title: 'Not Allowed — Regulated Services',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Zanzo is not a regulated or professional services platform. '
                'The following are not allowed:',
                style: legalBodyStyle,
              ),
              SizedBox(height: 8),
              LegalBullet(
                'Adult, sexual, escort, intimate, or massage-type tasks',
              ),
              LegalBullet(
                'Childcare, elderly care, personal care, or emotional support services',
              ),
              LegalBullet('Medical assistance or nursing'),
              LegalBullet('Regulated care or support work'),
              LegalBullet('Passenger transport or driving people anywhere'),
            ],
          ),
        ),
        LegalSection(
          icon: Icons.construction_outlined,
          title: 'Not Allowed — Skilled or Dangerous Work',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tasks requiring specialist skills, certification, or that '
                'carry physical risk are not allowed:',
                style: legalBodyStyle,
              ),
              SizedBox(height: 8),
              LegalBullet('Electrical work or wiring'),
              LegalBullet('Gas work or boiler servicing'),
              LegalBullet('Plumbing repairs'),
              LegalBullet('Broadband, router, or IT repairs'),
              LegalBullet('Appliance repairs'),
              LegalBullet('Car repairs or servicing'),
              LegalBullet('Locksmith work'),
              LegalBullet('Pest control'),
              LegalBullet('Any regulated trade'),
              LegalBullet('Use of ladders or work at height'),
              LegalBullet('Roof work'),
              LegalBullet('Heavy lifting'),
              LegalBullet('Chemical use'),
              LegalBullet('Power tools'),
            ],
          ),
        ),
        LegalSection(
          icon: Icons.gavel_outlined,
          title: 'Not Allowed — Conduct',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Tasks or behaviour that involve any of the following are '
                'strictly prohibited:',
                style: legalBodyStyle,
              ),
              SizedBox(height: 8),
              LegalBullet('Illegal, unlawful, or suspicious activity'),
              LegalBullet('Harassment, abuse, or threatening behaviour'),
              LegalBullet('Stalking or following someone'),
              LegalBullet('Discriminatory or hateful conduct'),
              LegalBullet('Attempting to deceive or mislead'),
              LegalBullet('Endangering the safety of anyone'),
            ],
          ),
        ),
        LegalSection(
          icon: Icons.shield_outlined,
          title: 'General Safety Rules',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LegalBullet(
                'If a task feels unclear, unsafe, illegal, or outside these '
                'rules — do not proceed.',
                strong: true,
              ),
              LegalBullet(
                'Zanzo may reject, pause, or cancel tasks that appear to '
                'breach these rules.',
              ),
              LegalBullet(
                'Both customers and ZanCrew are responsible for honest, '
                'safe, and respectful conduct.',
              ),
              LegalBullet(
                'Zanzo is not an emergency service. If someone is in danger, '
                'call 999 immediately.',
                strong: true,
              ),
            ],
          ),
        ),
        LegalSection(
          icon: Icons.support_agent_outlined,
          title: 'If You\'re Unsure',
          child: Text(
            'If you\'re not sure whether a task is acceptable before '
            'submitting or accepting it, please contact support first. '
            'We would rather you ask than have a task go wrong for anyone '
            'involved. Zanzo support can review unclear situations and '
            'advise you.',
            style: legalBodyStyle,
          ),
        ),
      ],
    );
  }
}
