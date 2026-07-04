// Three-step phone login:
//   Step 1 — phone number + country prefix → Send OTP
//   Step 2 — 6-digit OTP boxes             → Verify  (tokens saved here)
//   Step 3 — name input                    → Continue (new users only)
//
// lib/features/user/widgets/login_prompt_dialog.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zanzo_frontend/core/services/api_service.dart';
import 'package:zanzo_frontend/core/services/location_helper.dart';

enum _Step { phone, otp, name }

// Zanzo palette
const _kSaffron = Color(0xFFD97706);
const _kInk = Color(0xFF26211C);
const _kMuted = Color(0xFF8C8378);
const _kBg = Color(0xFFFCFAF6);
const _kLine = Color(0xFFE8E2D9);

const _footerStyle = TextStyle(fontSize: 11.5, color: _kMuted, height: 1.5);

/// Opens the login dialog. Returns true when the session is fully established.
Future<bool> showLoginPrompt(BuildContext context) async {
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _LoginPromptDialog(),
      ) ??
      false;
}

// ─────────────────────────────────────────────────────────────────────────────

class _LoginPromptDialog extends StatefulWidget {
  const _LoginPromptDialog();

  @override
  State<_LoginPromptDialog> createState() => _LoginPromptDialogState();
}

class _LoginPromptDialogState extends State<_LoginPromptDialog> {
  // Step 1 — phone
  final _phoneCtrl = TextEditingController();
  String _prefix = '+44'; // default UK; overridden from prefs if IN

  // Step 2 — OTP
  final _otpCtrl = TextEditingController();
  final _otpFocus = FocusNode();

  // Step 3 — name
  final _nameCtrl = TextEditingController();

  _Step _step = _Step.phone;
  bool _sending = false;
  String? _error;

  // ── Init / dispose ───────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _readCountryCode();
  }

  /// Default to +91 if the stored country_code is IN; keep +44 otherwise.
  Future<void> _readCountryCode() async {
    final prefs = await SharedPreferences.getInstance();
    final cc = prefs.getString('country_code');
    if (cc == 'IN' && mounted) setState(() => _prefix = '+91');
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    _otpFocus.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Converts the local number + prefix into E.164.
  /// Handles: "7700123456", "07700123456", "+447700123456"
  String get _e164Phone {
    var local = _phoneCtrl.text.trim().replaceAll(RegExp(r'[\s\-]'), '');
    if (local.startsWith('+')) return local; // user pasted full E.164
    if (local.startsWith('0')) local = local.substring(1); // strip leading 0
    return '$_prefix$local';
  }

  String get _prefixFlag => switch (_prefix) {
    '+44' => '🇬🇧',
    '+91' => '🇮🇳',
    _ => '🌐',
  };

  // ── FCM — fire-and-forget after tokens are saved ─────────────────────────

  Future<void> _registerFcmToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      final platform = Platform.isIOS ? 'ios' : 'android';
      await ApiService.registerDeviceToken(token: token, platform: platform);
    } catch (_) {}
  }

  // ── Step 1 — send OTP ────────────────────────────────────────────────────

  Future<void> _sendOtp() async {
    final e164 = _e164Phone;
    // Minimum plausibility: prefix + at least 7 digits
    if (_phoneCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Enter your phone number.');
      return;
    }
    final digitsOnly = e164.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.length < 9) {
      setState(() => _error = 'Enter a valid phone number.');
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final res = await ApiService.httpClient.post(
        Uri.parse('${ApiService.baseUrl}/auth/send-phone-otp'),
        headers: ApiService.jsonHeaders,
        body: jsonEncode({'phone': e164}),
      );
      if (!mounted) return;
      if (res.statusCode >= 200 && res.statusCode < 300) {
        setState(() => _step = _Step.otp);
      } else {
        setState(() => _error = 'Failed to send OTP. (${res.statusCode})');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Network error: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ── Step 2 — verify OTP ───────────────────────────────────────────────────

  Future<void> _verifyOtp() async {
    final otp = _otpCtrl.text.trim();
    if (otp.length != 6) {
      setState(() => _error = 'Enter the full 6-digit code.');
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final res = await ApiService.httpClient.post(
        Uri.parse('${ApiService.baseUrl}/auth/verify-phone-otp'),
        headers: ApiService.jsonHeaders,
        body: jsonEncode({'phone': _e164Phone, 'code': otp}),
      );
      if (!mounted) return;

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(res.body);
        final user = decoded['user'] ?? {};
        final prefs = await SharedPreferences.getInstance();

        await prefs.setString('user_phone', _e164Phone);
        await prefs.setBool('phone_verified', true);

        final userId = (user['id'] ?? '').toString();
        if (userId.isNotEmpty) await prefs.setString('user_id', userId);

        final access = decoded['access_token']?.toString();
        final refresh = decoded['refresh_token']?.toString();
        if (access != null && access.isNotEmpty) {
          await prefs.setString('access_token', access);
        }
        if (refresh != null && refresh.isNotEmpty) {
          await prefs.setString('refresh_token', refresh);
        }

        await prefs.setString('zancrew_status', 'pending');
        await prefs.setBool('zancrew_enabled', false);

        final backendEmail = (user['email'] as String?)?.trim();
        if (backendEmail != null && backendEmail.isNotEmpty) {
          await prefs.setString('user_email', backendEmail);
        }

        // FCM + location: best-effort, non-blocking
        unawaited(_registerFcmToken());
        try {
          await LocationHelper.getCurrentLocation();
        } catch (_) {}

        final backendName = (user['full_name'] as String?)?.trim();
        if (backendName != null && backendName.isNotEmpty) {
          // Existing user — no need to ask for name again.
          await prefs.setString('user_name', backendName);
          if (mounted) Navigator.of(context).pop(true);
        } else {
          // New user — collect name.
          if (mounted) setState(() => _step = _Step.name);
        }
      } else {
        setState(() => _error = 'Invalid OTP. (${res.statusCode})');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Network error: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ── Step 3 — save name ───────────────────────────────────────────────────

  Future<void> _saveName() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter your name to continue.');
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final updated = await ApiService.patchProfile({'name': name});
      if (!mounted) return;

      final confirmed = (updated?['full_name'] as String?)?.trim();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'user_name',
        (confirmed != null && confirmed.isNotEmpty) ? confirmed : name,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Network error: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ── UI strings ───────────────────────────────────────────────────────────

  String get _title => switch (_step) {
    _Step.phone => 'Sign in',
    _Step.otp => 'Verify code',
    _Step.name => 'What should we call you?',
  };

  String get _subtitle => switch (_step) {
    _Step.phone => 'Enter your number to get started.',
    _Step.otp => 'We sent a code to $_e164Phone.',
    _Step.name => 'This is how helpers will know you.',
  };

  String get _buttonLabel => switch (_step) {
    _Step.phone => 'Send OTP',
    _Step.otp => 'Verify',
    _Step.name => 'Continue',
  };

  Future<void> Function() get _primaryAction => switch (_step) {
    _Step.phone => _sendOtp,
    _Step.otp => _verifyOtp,
    _Step.name => _saveName,
  };

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: _kBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title
            Text(
              _title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: _kInk,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            // Subtitle
            Text(
              _subtitle,
              style: const TextStyle(
                fontSize: 13,
                color: _kMuted,
                fontWeight: FontWeight.w400,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 20),

            // Input area — separate widget per step so Flutter always creates
            // a new FocusNode / keyboard connection when the step changes.
            if (_step == _Step.phone)
              _buildPhoneStep()
            else if (_step == _Step.otp)
              _buildOtpBoxes()
            else
              TextField(
                key: const ValueKey(_Step.name),
                controller: _nameCtrl,
                keyboardType: TextInputType.name,
                textCapitalization: TextCapitalization.words,
                textInputAction: TextInputAction.done,
                autofocus: true,
                onSubmitted: (_) => _sending ? null : _saveName(),
                decoration: _inputDeco('Your name', 'e.g. Alex'),
              ),

            // Error
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(
                  color: Color(0xFFDC2626),
                  fontSize: 13,
                  height: 1.3,
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (_step != _Step.name) ...[
                  TextButton(
                    onPressed: _sending
                        ? null
                        : () => Navigator.of(context).pop(false),
                    style: TextButton.styleFrom(foregroundColor: _kMuted),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                ],
                SizedBox(
                  height: 44,
                  child: ElevatedButton(
                    onPressed: _sending ? null : _primaryAction,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kSaffron,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: _kLine,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      textStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    child: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(_buttonLabel),
                  ),
                ),
              ],
            ),

            // Legal consent footer — shown on phone step only
            if (_step == _Step.phone) ...[
              const SizedBox(height: 16),
              _buildLegalFooter(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLegalFooter() {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        const Text('By continuing, you agree to our ', style: _footerStyle),
        _legalTap('Terms', '/terms'),
        const Text(', ', style: _footerStyle),
        _legalTap('Privacy Policy', '/privacy'),
        const Text(' and ', style: _footerStyle),
        _legalTap('Task Rules', '/task_rules'),
        const Text('.', style: _footerStyle),
      ],
    );
  }

  Widget _legalTap(String label, String route) {
    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, route),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11.5,
          color: _kSaffron,
          height: 1.5,
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.underline,
          decorationColor: _kSaffron,
        ),
      ),
    );
  }

  // ── Phone step — prefix picker + number field ─────────────────────────────

  Widget _buildPhoneStep() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Country prefix popup button
        PopupMenuButton<String>(
          initialValue: _prefix,
          onSelected: (v) => setState(() => _prefix = v),
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: _kLine),
          ),
          itemBuilder: (_) => const [
            PopupMenuItem(
              value: '+44',
              child: Text('🇬🇧  +44  United Kingdom'),
            ),
            PopupMenuItem(value: '+91', child: Text('🇮🇳  +91  India')),
          ],
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _kLine),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_prefixFlag, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 4),
                Text(
                  _prefix,
                  style: const TextStyle(
                    color: _kInk,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(width: 2),
                const Icon(Icons.expand_more, size: 16, color: _kMuted),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Local number input
        Expanded(
          child: TextField(
            key: const ValueKey(_Step.phone),
            controller: _phoneCtrl,
            keyboardType: TextInputType.phone,
            textInputAction: TextInputAction.done,
            autofocus: true,
            onSubmitted: (_) => _sending ? null : _sendOtp(),
            decoration: _inputDeco('Number', '7700 123456'),
          ),
        ),
      ],
    );
  }

  // ── OTP step — 6 visual boxes over a hidden capture field ─────────────────

  Widget _buildOtpBoxes() {
    final typed = _otpCtrl.text;
    return SizedBox(
      key: const ValueKey(_Step.otp),
      height: 56,
      child: Stack(
        children: [
          // Invisible TextField fills the full area and captures keyboard input.
          Positioned.fill(
            child: Opacity(
              opacity: 0,
              child: TextField(
                controller: _otpCtrl,
                focusNode: _otpFocus,
                keyboardType: TextInputType.number,
                maxLength: 6,
                autofocus: true,
                decoration: const InputDecoration(counterText: ''),
                onChanged: (v) {
                  setState(() {});
                  // Auto-submit on 6 digits
                  if (v.length == 6 && !_sending) _verifyOtp();
                },
              ),
            ),
          ),
          // Visual digit boxes — IgnorePointer passes touches to the hidden field.
          IgnorePointer(
            child: Row(
              children: List.generate(6, (i) {
                final char = i < typed.length ? typed[i] : '';
                final isActive = typed.length < 6 && i == typed.length;
                return Expanded(
                  child: Container(
                    margin: EdgeInsets.only(left: i == 0 ? 0 : 6),
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isActive
                            ? _kSaffron
                            : (char.isNotEmpty
                                  ? _kInk.withValues(alpha: 0.25)
                                  : _kLine),
                        width: isActive ? 1.5 : 1.0,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        char,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: _kInk,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  // ── Shared input decoration ───────────────────────────────────────────────

  InputDecoration _inputDeco(String label, String hint) => InputDecoration(
    labelText: label,
    hintText: hint,
    labelStyle: const TextStyle(color: _kMuted, fontSize: 14),
    hintStyle: TextStyle(color: _kLine.withValues(alpha: 0.8), fontSize: 14),
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _kLine),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: _kSaffron, width: 1.5),
    ),
  );
}
