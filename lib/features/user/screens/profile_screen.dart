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
  // Warm Zanzo palette
  static const Color _accent = Color(0xFFD97706);
  static const Color _bg = Color(0xFFFCFAF6);
  static const Color _surface = Color(0xFFF5F2EE);
  static const Color _card = Colors.white;
  static const Color _ink = Color(0xFF26211C);
  static const Color _muted = Color(0xFF8C8378);
  static const Color _line = Color(0xFFE8E2D9);
  static const Color _success = Color(0xFF16A34A);
  static const Color _warning = Color(0xFFF59E0B);

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

  // ---------------------------------------------------------------------------
  // DISPLAY HELPERS
  // ---------------------------------------------------------------------------

  /// Capitalises the first letter of each word; trims whitespace. Display-only.
  String _displayName(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '—';
    return raw
        .trim()
        .split(RegExp(r'\s+'))
        .map((w) {
          if (w.isEmpty) return w;
          return w[0].toUpperCase() + w.substring(1);
        })
        .join(' ');
  }

  /// Formats a +44 number as "+44 XXXX XXXXXX". Display-only.
  String _formatPhone(String? phone) {
    if (phone == null || phone.isEmpty) return '—';
    final s = phone.trim();
    if (RegExp(r'^\+44\d{10}$').hasMatch(s)) {
      return '${s.substring(0, 3)} ${s.substring(3, 7)} ${s.substring(7)}';
    }
    return s;
  }

  @override
  Widget build(BuildContext context) {
    final signedIn = (_phone != null && _phone!.isNotEmpty);
    final initial = (_name?.trim().isNotEmpty ?? false)
        ? _name![0].toUpperCase()
        : '?';

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text(
          "Profile",
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: _bg,
        foregroundColor: _ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _accent))
          : (!signedIn ? _loginRequired() : _profileBody(initial)),
    );
  }

  // ---------------------------------------------------------------------------
  // LOGIN REQUIRED
  // ---------------------------------------------------------------------------
  Widget _loginRequired() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_outline_rounded,
              size: 64,
              color: _accent.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              "Sign in to view your profile",
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Track orders, manage your account, and more.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: _muted),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _accent,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 14,
                ),
              ),
              onPressed: _signIn,
              child: const Text(
                "Sign in",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
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
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: _accent.withValues(alpha: 0.12),
                    child: Text(
                      initial,
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: _accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _displayName(_name),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: _ink,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            _trustPill(Icons.verified, 'Verified'),
                            _trustPill(Icons.lock_outline, 'Secure'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: _line),
            _accountRow(
              icon: Icons.phone_outlined,
              label: 'Phone',
              value: _formatPhone(_phone),
              action: 'Change',
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
            Divider(height: 1, color: _line),
            _accountRow(
              icon: Icons.mail_outline_rounded,
              label: 'Email',
              value: _email?.isNotEmpty == true ? _email! : 'Not added',
              caption: _email?.isNotEmpty == true
                  ? null
                  : 'Add for receipts & recovery',
              action: (_email?.isNotEmpty ?? false) ? 'Edit' : 'Add',
              onTap: () async {
                final prefs = await SharedPreferences.getInstance();
                final token = prefs.getString('access_token');
                if (token == null) return _signIn();
                final result = await showAddEmailDialog(
                  context,
                  current: _email,
                );
                if (result == true) setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _trustPill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: _accent),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: _ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _accountRow({
    required IconData icon,
    required String label,
    required String value,
    String? caption,
    required String action,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 13, 14, 13),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 18, color: _muted),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _muted,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    ),
                  ),
                  if (caption != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      caption,
                      style: const TextStyle(fontSize: 12, color: _muted),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              action,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: _accent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ZANCrew CARD
  // ---------------------------------------------------------------------------
  Widget _zanCrewCard() {
    final Color fg;
    final Color bg;
    switch (_zancrewStatus) {
      case 'active':
        fg = _success;
        bg = const Color(0xFFDCFCE7);
        break;
      case 'pending':
        fg = _warning;
        bg = const Color(0xFFFEF3C7);
        break;
      case 'rejected':
        fg = const Color(0xFFDC2626);
        bg = const Color(0xFFFFEBEB);
        break;
      default:
        fg = _muted;
        bg = _surface;
    }

    const int chipMax = 3;
    final visible = _zancrewBuckets.take(chipMax).toList();
    final overflow = _zancrewBuckets.length - chipMax;

    final statusLabel = _zancrewStatus == 'active'
        ? 'Active'
        : _zancrewStatus == 'pending'
        ? 'Pending'
        : _zancrewStatus == 'rejected'
        ? 'Rejected'
        : 'Off';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title + status badge on same row
          Row(
            children: [
              const Expanded(
                child: Text(
                  'ZanCrew',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: fg.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: fg,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      statusLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_zancrewBuckets.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              '${_zancrewBuckets.length} '
              '${_zancrewBuckets.length == 1 ? 'service' : 'services'}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _muted,
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ...visible.map(
                  (b) => Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _line),
                    ),
                    child: Text(
                      b,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _ink,
                      ),
                    ),
                  ),
                ),
                if (overflow > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _line),
                    ),
                    child: Text(
                      '+$overflow more',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _muted,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ACTIONS
  // ---------------------------------------------------------------------------
  Widget _actionsCard() {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const JobHistoryScreen()),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.history_rounded, color: _accent, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "My Orders",
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _ink,
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right, color: _muted),
                    ],
                  ),
                ),
              ),
            ),
            Divider(height: 1, color: _line),
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {},
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.settings_outlined, color: _muted, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "Settings",
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _ink,
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right, color: _muted),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
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
