import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Core services
import 'package:zanzo_frontend/core/services/auth.dart';
import 'package:zanzo_frontend/core/services/uk_provider_api.dart';
import 'package:zanzo_frontend/core/services/zancrew_api.dart';
// Dialogs & widgets
import 'package:zanzo_frontend/core/widgets/verify_phone_otp_dialog.dart';
// Screens
import 'package:zanzo_frontend/features/user/screens/job_history_screen.dart';
import 'package:zanzo_frontend/features/user/widgets/add_email_dialog.dart';
import 'package:zanzo_frontend/features/user/widgets/change_phone_dialog.dart';
import 'package:zanzo_frontend/features/user/widgets/login_prompt_dialog.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _name;
  String? _phone;
  String? _email;
  bool _loading = true;

  // ZanCrew state
  bool _zancrewEnabled = false;
  String _zancrewStatus = 'off';
  List<String> _zancrewBuckets = const [];
  bool _bankVerified = false;
  bool _kycVerified = false;

  Color get purple => const Color(0xFF6C4DFF);

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  // ---------------------------------------------------------------------------
  // LOAD PROFILE
  // ---------------------------------------------------------------------------
  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('user_id');

    if (uid != null) {
      try {
        final profile = await ZanCrewApi.getProfile(uid);
        if (profile != null) {
          await prefs.setString('zancrew_status', profile['status'] ?? 'off');
          await prefs.setStringList(
            'zancrew_buckets',
            (profile['buckets'] as List?)?.map((e) => e.toString()).toList() ??
                <String>[],
          );
          await prefs.setBool(
            'zancrew_bank_verified',
            profile['bank_verified'] ?? false,
          );
          await prefs.setBool(
            'zancrew_kyc_verified',
            profile['kyc_verified'] ?? false,
          );
        }
      } catch (_) {}

      // UK provider status is the authoritative approval gate — override
      // zancrew_status and zancrew_enabled based on it so the profile card
      // shows the correct state regardless of zancrew_profiles.status.
      try {
        final ukStatus = await UkProviderApi.getStatus(uid);
        if (ukStatus != null) {
          final providerStatus = ukStatus['provider_status'] as String? ?? '';
          final canReceive = ukStatus['can_receive_offers'] == true;
          if (providerStatus == 'approved' && canReceive) {
            await prefs.setString('zancrew_status', 'active');
            await prefs.setBool('zancrew_enabled', true);
          } else if (providerStatus == 'pending') {
            await prefs.setString('zancrew_status', 'pending');
          } else if (providerStatus == 'rejected' ||
              providerStatus == 'suspended') {
            await prefs.setString('zancrew_status', 'rejected');
          }
        }
      } catch (_) {}
    }

    setState(() {
      _name = prefs.getString('user_name');
      _phone = prefs.getString('user_phone');
      _email = prefs.getString('user_email');

      _zancrewStatus = prefs.getString('zancrew_status') ?? 'off';
      _zancrewBuckets = prefs.getStringList('zancrew_buckets') ?? <String>[];
      _bankVerified = prefs.getBool('zancrew_bank_verified') ?? false;
      _kycVerified = prefs.getBool('zancrew_kyc_verified') ?? false;

      _loading = false;
    });
  }

  // ---------------------------------------------------------------------------
  // AUTH
  // ---------------------------------------------------------------------------
  Future<void> _signIn() async {
    final ok = await showLoginPrompt(context);
    if (!mounted) return;
    if (ok) await _loadProfile();
  }

  Future<void> _logout() async {
    await Auth.signOut();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, '/home', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = (_phone != null && _phone!.isNotEmpty);
    final initial = (_name?.trim().isNotEmpty ?? false)
        ? _name![0].toUpperCase()
        : '?';

    return Scaffold(
      appBar: AppBar(
        title: const Text("Profile"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (!signedIn ? _loginRequired() : _profileBody(initial)),
    );
  }

  // ---------------------------------------------------------------------------
  // LOGIN REQUIRED
  // ---------------------------------------------------------------------------
  Widget _loginRequired() {
    return Center(
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: purple,
          foregroundColor: Colors.white,
        ),
        onPressed: _signIn,
        child: const Text("Sign in"),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // MAIN BODY
  // ---------------------------------------------------------------------------
  Widget _profileBody(String initial) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _identityHeader(initial),
          const SizedBox(height: 18),
          _zanCrewCard(),
          const SizedBox(height: 18),
          _actionsCard(),
          const SizedBox(height: 20),
          _logoutButton(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // IDENTITY HEADER
  // ---------------------------------------------------------------------------
  Widget _identityHeader(String initial) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: purple.withOpacity(0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: purple.withOpacity(0.12)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: purple.withOpacity(0.15),
                child: Text(
                  initial,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: purple,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _name ?? '—',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        _trustPill(Icons.verified, "Phone verified"),
                        _trustPill(Icons.lock_outline, "Secure account"),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _contactRow(
            label: "Phone",
            value: _phone ?? '—',
            action: "Change",
            onTap: () async {
              final newPhone = await showChangePhoneDialog(
                context,
                currentPhone: _phone,
              );
              if (newPhone is String) {
                final verified = await showVerifyPhoneOtpDialog(
                  context,
                  newPhone: newPhone,
                );
                if (verified == true) await _loadProfile();
              }
            },
          ),
          const SizedBox(height: 12),
          _contactRow(
            label: "Email",
            value: _email?.isNotEmpty == true ? _email! : "Optional",
            helper: _email?.isNotEmpty == true
                ? null
                : "Add email for receipts & recovery",
            action: (_email?.isNotEmpty ?? false) ? "Edit" : "Add",
            onTap: () async {
              final prefs = await SharedPreferences.getInstance();
              final token = prefs.getString('access_token');
              if (token == null) return _signIn();

              final result = await showAddEmailDialog(context, current: _email);
              if (result == true) setState(() {});
            },
          ),
        ],
      ),
    );
  }

  Widget _trustPill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: purple),
          const SizedBox(width: 6),
          Text(
            text,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _contactRow({
    required String label,
    required String value,
    String? helper,
    required String action,
    required VoidCallback onTap,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (helper != null) ...[
                const SizedBox(height: 4),
                Text(
                  helper,
                  style: const TextStyle(fontSize: 12, color: Colors.black45),
                ),
              ],
            ],
          ),
        ),
        TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            foregroundColor: purple,
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          child: Text(action),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // ZANCrew CARD
  // ---------------------------------------------------------------------------
  Widget _zanCrewCard() {
    final statusColor = {
      'active': Colors.green[700],
      'pending': Colors.orange[700],
      'rejected': Colors.red[700],
      'off': Colors.black54,
    }[_zancrewStatus]!;

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "ZanCrew Status",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: purple,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.work_outline, color: statusColor),
                const SizedBox(width: 8),
                Text(
                  _zancrewStatus.toUpperCase(),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: statusColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_zancrewBuckets.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _zancrewBuckets
                    .map(
                      (b) => Chip(
                        label: Text(b),
                        backgroundColor: purple.withOpacity(0.12),
                        labelStyle: TextStyle(color: purple),
                      ),
                    )
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------
  Widget _actionsCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          ListTile(
            leading: Icon(Icons.history, color: purple),
            title: const Text("My Orders"),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const JobHistoryScreen()),
              );
            },
          ),
          const Divider(height: 1),
          ListTile(
            leading: Icon(Icons.settings, color: purple),
            title: const Text("Settings"),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // LOGOUT
  // ---------------------------------------------------------------------------
  Widget _logoutButton() {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: _logout,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.red.shade700,
          side: BorderSide(color: Colors.red.shade200),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14),
        ),
        child: const Text(
          "Logout",
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
