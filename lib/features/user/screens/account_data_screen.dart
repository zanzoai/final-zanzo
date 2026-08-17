// lib/features/user/screens/account_data_screen.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zanzo_frontend/core/services/api_service.dart';
import 'package:zanzo_frontend/core/widgets/skeleton.dart';

const _kBg = Color(0xFFFCFAF6);
const _kInk = Color(0xFF26211C);
const _kMuted = Color(0xFF8C8378);
const _kLine = Color(0xFFE8E2D9);
const _kSaffron = Color(0xFFD97706);
const _kAmberLight = Color(0xFFFEF3C7);

class AccountDataScreen extends StatefulWidget {
  const AccountDataScreen({super.key});

  static const routeName = '/account_data';

  @override
  State<AccountDataScreen> createState() => _AccountDataScreenState();
}

class _AccountDataScreenState extends State<AccountDataScreen> {
  String? _name;
  String? _phone;
  String? _email;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _name = prefs.getString('user_name');
      _phone = prefs.getString('user_phone');
      _email = prefs.getString('user_email');
      _loading = false;
    });
  }

  Future<void> _requestDeletion(String requestType) async {
    final isAccount = requestType == 'account_deletion';
    final title = isAccount
        ? 'Request account deletion?'
        : 'Request data deletion?';
    final intro = isAccount
        ? 'This sends a request to Zanzo. Your account will not be deleted immediately.'
        : 'This sends a request to Zanzo to review removal of your personal data.';

    final reasonCtrl = TextEditingController();
    Map<String, dynamic>? result;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        var submitting = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: _kInk,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      intro,
                      style: const TextStyle(
                        fontSize: 14,
                        color: _kInk,
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _dialogBullet('Zanzo will review your request first.'),
                    const SizedBox(height: 7),
                    _dialogBullet(
                      'Some records may be retained for payments, disputes, '
                      'safety, fraud prevention, or legal reasons.',
                    ),
                    const SizedBox(height: 7),
                    _dialogBullet(
                      'If you have an active task, complete or cancel it first.',
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: reasonCtrl,
                      enabled: !submitting,
                      maxLines: 3,
                      maxLength: 500,
                      style: const TextStyle(fontSize: 14, color: _kInk),
                      decoration: InputDecoration(
                        hintText: 'Optional: add a reason',
                        hintStyle: const TextStyle(
                          color: _kMuted,
                          fontSize: 14,
                        ),
                        counterStyle: const TextStyle(
                          color: _kMuted,
                          fontSize: 11,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: _kLine),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: _kLine),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(
                            color: _kSaffron,
                            width: 1.5,
                          ),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              actions: [
                TextButton(
                  onPressed: submitting ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel', style: TextStyle(color: _kMuted)),
                ),
                FilledButton(
                  onPressed: submitting
                      ? null
                      : () async {
                          setDialogState(() => submitting = true);
                          final reason = reasonCtrl.text.trim();
                          final r = await ApiService.requestPrivacy(
                            requestType,
                            reason: reason.isNotEmpty ? reason : null,
                          );
                          result = r;
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                        },
                  style: FilledButton.styleFrom(
                    backgroundColor: _kSaffron,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Submit request'),
                ),
              ],
            );
          },
        );
      },
    );

    reasonCtrl.dispose();
    if (!mounted || result == null) return;
    _showResult(result!);
  }

  void _showResult(Map<String, dynamic> result) {
    final statusCode = result['statusCode'] as int? ?? 0;
    final backendMessage = result['message'] as String? ?? '';

    final String text;
    final bool success;
    if (statusCode == 202) {
      text = 'Request submitted. Zanzo will review and process it.';
      success = true;
    } else if (statusCode == 409 && backendMessage.isNotEmpty) {
      text = backendMessage;
      success = false;
    } else {
      text = "Couldn't submit request. Please try again.";
      success = false;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: success ? const Color(0xFF16A34A) : _kInk,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        title: const Text(
          'Account & Data',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: _kBg,
        foregroundColor: _kInk,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: _loading
          ? _accountSkeleton()
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _sectionLabel('ACCOUNT INFORMATION'),
                  _infoCard(),
                  const SizedBox(height: 24),
                  _sectionLabel('YOUR DATA & PRIVACY'),
                  _privacyCard(),
                  const SizedBox(height: 24),
                  _noteCard(),
                ],
              ),
            ),
    );
  }

  // Shimmer shaped like this screen: two labelled sections — an info card with
  // three value rows, then a privacy card with action rows.
  Widget _accountSkeleton() {
    const divider = Divider(height: 1, color: Color(0x11000000));
    Widget label() => const Padding(
      padding: EdgeInsets.only(left: 4, bottom: 12),
      child: SkeletonBone(width: 150, height: 11),
    );
    Widget infoRow() => const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: Row(
        children: [
          SkeletonLine(widthFactor: 0.22, height: 13),
          Spacer(),
          SkeletonBone(width: 120, height: 13),
        ],
      ),
    );
    Widget actionRow() => const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 17),
      child: Row(
        children: [
          SkeletonBone(
            width: 34,
            height: 34,
            radius: BorderRadius.all(Radius.circular(9)),
          ),
          SizedBox(width: 14),
          Expanded(child: SkeletonLine(widthFactor: 0.5, height: 14)),
          SizedBox(width: 12),
          SkeletonBone(width: 16, height: 16),
        ],
      ),
    );

    return Shimmer(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          label(),
          SkeletonCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [infoRow(), divider, infoRow(), divider, infoRow()],
            ),
          ),
          const SizedBox(height: 24),
          label(),
          SkeletonCard(
            padding: EdgeInsets.zero,
            child: Column(children: [actionRow(), divider, actionRow()]),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 10),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _kMuted,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  Widget _infoCard() {
    final name = (_name?.trim().isNotEmpty == true) ? _name! : '—';
    final phone = (_phone?.trim().isNotEmpty == true) ? _phone! : '—';
    final email = (_email?.trim().isNotEmpty == true) ? _email! : '—';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kLine),
      ),
      child: Column(
        children: [
          _infoRow('Name', name),
          const Divider(height: 1, color: _kLine, indent: 16, endIndent: 16),
          _infoRow('Phone', phone),
          const Divider(height: 1, color: _kLine, indent: 16, endIndent: 16),
          _infoRow('Email', email),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: _kMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                color: _kInk,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _privacyCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kLine),
      ),
      child: Column(
        children: [
          _actionRow(
            icon: Icons.manage_accounts_outlined,
            title: 'Request account deletion',
            subtitle: 'Ask Zanzo to review and close your account',
            onTap: () => _requestDeletion('account_deletion'),
            showDivider: true,
          ),
          _actionRow(
            icon: Icons.privacy_tip_outlined,
            title: 'Request data deletion',
            subtitle: 'Ask Zanzo to review removal of your personal data',
            onTap: () => _requestDeletion('data_deletion'),
            showDivider: false,
          ),
        ],
      ),
    );
  }

  Widget _actionRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required bool showDivider,
  }) {
    return Column(
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: showDivider
                ? BorderRadius.zero
                : const BorderRadius.vertical(bottom: Radius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _kAmberLight,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 19, color: _kSaffron),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _kInk,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: const TextStyle(
                            fontSize: 12,
                            color: _kMuted,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(Icons.chevron_right, color: _kMuted, size: 20),
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          const Divider(height: 1, color: _kLine, indent: 68, endIndent: 0),
      ],
    );
  }

  Widget _dialogBullet(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2.5),
          child: Text('•', style: TextStyle(fontSize: 14, color: _kMuted)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13.5,
              color: _kMuted,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }

  Widget _noteCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF9EC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: _kSaffron),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Requests are reviewed manually by the Zanzo team. '
              'Some data may be retained for legal, safety, and financial compliance reasons.',
              style: TextStyle(fontSize: 12.5, color: _kInk, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
