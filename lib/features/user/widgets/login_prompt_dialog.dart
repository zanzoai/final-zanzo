// This popup handles Name + Phone login using OTP.
// Step 1: Collect name + phone → Send OTP
// Step 2: Enter OTP → Verify OTP → Save session to SharedPreferences
// Returns: true when the login is successful.
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

/// Public entry → Opens the login dialog.
/// Returns true when login process success (OTP verified).
Future<bool> showLoginPrompt(BuildContext context) async {
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const _LoginPromptDialog(),
      ) ??
      false;
}

class _LoginPromptDialog extends StatefulWidget {
  const _LoginPromptDialog();

  @override
  State<_LoginPromptDialog> createState() => _LoginPromptDialogState();
}

class _LoginPromptDialogState extends State<_LoginPromptDialog> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _otp = TextEditingController();

  bool _sending = false;
  bool _sent = false; // OTP already sent
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _otp.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // FCM TOKEN — best-effort, runs after access_token is saved
  // ---------------------------------------------------------------------------
  Future<void> _registerFcmToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      final platform = Platform.isIOS ? 'ios' : 'android';
      await ApiService.registerDeviceToken(token: token, platform: platform);
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // SEND OTP → Step 1
  // ---------------------------------------------------------------------------
  Future<void> _sendOtp() async {
    setState(() {
      _sending = true;
      _error = null;
    });

    final name = _name.text.trim();
    final phone = _phone.text.trim();

    // --- Validation ---
    if (name.isEmpty || phone.isEmpty) {
      setState(() {
        _sending = false;
        _error = 'Please enter your name and phone number.';
      });
      return;
    }

    if (!phone.startsWith('+')) {
      setState(() {
        _sending = false;
        _error = 'Phone number must start with + (e.g., +91XXXXXXXXXX).';
      });
      return;
    }

    try {
      final url = Uri.parse("${ApiService.baseUrl}/auth/send-phone-otp");
      final res = await ApiService.httpClient.post(
        url,
        headers: ApiService.jsonHeaders,
        body: jsonEncode({'phone': phone}),
      );

      if (!mounted) return;

      if (res.statusCode >= 200 && res.statusCode < 300) {
        // Store the name before OTP stage
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('user_name', name);

        setState(() => _sent = true);
      } else {
        setState(() => _error = "Failed to send OTP. (${res.statusCode})");
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = "Network error: $e");
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ---------------------------------------------------------------------------
  // VERIFY OTP → Step 2
  // ---------------------------------------------------------------------------
  Future<void> _verifyOtp() async {
    setState(() {
      _sending = true;
      _error = null;
    });

    final otp = _otp.text.trim();
    final phone = _phone.text.trim();

    if (otp.isEmpty) {
      setState(() {
        _sending = false;
        _error = 'Enter the 6-digit OTP.';
      });
      return;
    }

    try {
      final url = Uri.parse("${ApiService.baseUrl}/auth/verify-phone-otp");
      final res = await ApiService.httpClient.post(
        url,
        headers: ApiService.jsonHeaders,
        body: jsonEncode({'phone': phone, 'code': otp}),
      );

      if (!mounted) return;

      if (res.statusCode >= 200 && res.statusCode < 300) {
        final decoded = jsonDecode(res.body);
        final user = decoded['user'] ?? {};

        final prefs = await SharedPreferences.getInstance();

        // DO NOT overwrite name here
        final String? savedName = prefs.getString('user_name');

        // Store essential data
        await prefs.setString('user_phone', phone);
        await prefs.setBool('phone_verified', true);

        final userId = (user['id'] ?? '').toString();
        if (userId.isNotEmpty) {
          await prefs.setString('user_id', userId);
        }

        // Optional tokens
        final access = decoded['access_token']?.toString();
        final refresh = decoded['refresh_token']?.toString();
        if (access != null && access.isNotEmpty) {
          await prefs.setString('access_token', access);
        }
        if (refresh != null && refresh.isNotEmpty) {
          await prefs.setString('refresh_token', refresh);
        }

        // ZanCrew defaults
        await prefs.setString('zancrew_status', 'pending');
        await prefs.setBool('zancrew_enabled', false);

        // Register FCM token for push notifications (all users: customer + crew)
        unawaited(_registerFcmToken());

        // Get GPS location and upgrade OTP token to geo-aware token.
        // Errors are swallowed so a denied permission never blocks login.
        try {
          await LocationHelper.getCurrentLocation();
        } catch (_) {}

        if (mounted) Navigator.of(context).pop(true);
      } else {
        setState(() => _error = "Invalid OTP. (${res.statusCode})");
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = "Network error: $e");
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sign in'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // -----------------------
            // NAME + PHONE
            // -----------------------
            if (!_sent) ...[
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _phone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  hintText: '+91XXXXXXXXXX',
                ),
              ),
            ]
            // -----------------------
            // OTP INPUT
            // -----------------------
            else ...[
              TextField(
                controller: _otp,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Enter OTP',
                  hintText: '6-digit code',
                ),
              ),
            ],

            // -----------------------
            // ERROR MESSAGE
            // -----------------------
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
          ],
        ),
      ),

      // -----------------------------------------------------------------------
      // ACTION BUTTONS
      // -----------------------------------------------------------------------
      actions: [
        TextButton(
          onPressed: _sending ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),

        // SEND OTP
        if (!_sent)
          ElevatedButton(
            onPressed: _sending ? null : _sendOtp,
            child: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Send OTP'),
          )
        // VERIFY OTP
        else
          ElevatedButton(
            onPressed: _sending ? null : _verifyOtp,
            child: _sending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Verify'),
          ),
      ],
    );
  }
}
