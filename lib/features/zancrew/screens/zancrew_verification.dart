// lib/features/zancrew/screens/zancrew_verification.dart
//
// ZanCrew Verification Flow
//
// Responsibilities:
//  1) Fetch verification flags from backend (PAN, Bank, Aadhaar, Selfie).
//  2) Let user enter PAN + Bank details and submit for verification.
//  3) Capture Aadhaar front/back + selfie (camera + optional OCR on front).
//  4) Call unified verification endpoint.
//  5) Show numbered error reasons when something fails.
//  6) When all four checks pass, show success overlay and navigate to dashboard.
//
// External services (must exist in your project):
//   - VerificationApi   (PAN/Bank/Unified calls)
//   - ZanCrewApi        (profile/status flags)
//   - ZanCrewDashboard  (destination after success)

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/verification_api.dart';
import '../../../core/services/zancrew_api.dart';
import '../dashboard/zancrew_dashboard.dart';

class ZanCrewVerification extends StatefulWidget {
  final String userId;

  const ZanCrewVerification({super.key, required this.userId});

  @override
  State<ZanCrewVerification> createState() => _ZanCrewVerificationState();
}

// ===========================================================================
// PART 1: STATE + INITIALISATION
// ===========================================================================

class _ZanCrewVerificationState extends State<ZanCrewVerification> {
  // ----- Overall status -----
  bool _loading = false;
  String _status = 'pending';

  // Truth from server:
  bool _kycVerified = false; // PAN
  bool _bankVerified = false; // Bank
  bool _aadhaarVerified = false; // Aadhaar OCR
  bool _selfieVerified = false; // Liveness + Face match

  // Expansion flags per section
  bool _expandPan = true;
  bool _expandBank = false;
  bool _expandAadhaar = false;
  bool _expandSelfie = false;

  // Form controllers
  final _formKey = GlobalKey<FormState>();
  final _fullNameCtrl = TextEditingController();
  final _panCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  final _accCtrl = TextEditingController();
  final _ifscCtrl = TextEditingController();
  final _aadhaarNumberCtrl = TextEditingController();

  // Media capture
  final _picker = ImagePicker();
  File? _aadhaarFront;
  File? _aadhaarBack;
  File? _selfie;

  // Cropped versions that we actually send
  File? _aadhaarFrontCropped;
  File? _aadhaarBackCropped;
  File? _selfieCropped;

  // Last unified verification response (for numbered errors)
  Map<String, dynamic>? _lastVerification;

  // Debug toggle: skip real checks on backend (for sandbox)
  bool _debugAutoVerify = false;

  // Success overlay
  bool _showSuccessOverlay = false;
  Timer? _successTimer;

  // Brand colours
  static const _brand = Color(0xFF5B3DF0);
  static const _accent = Color(0xFF00C389);
  static const _error = Color(0xFFE34D5D);
  static const _ink = Color(0xFF0F172A);

  @override
  void initState() {
    super.initState();
    _restoreDebugToggle().then((_) => _freshSync());
  }

  @override
  void dispose() {
    _successTimer?.cancel();
    _fullNameCtrl.dispose();
    _panCtrl.dispose();
    _dobCtrl.dispose();
    _accCtrl.dispose();
    _ifscCtrl.dispose();
    _aadhaarNumberCtrl.dispose();
    super.dispose();
  }

  // =======================================================================
  // PART 2: DEBUG FLAG + PROFILE SYNC
  // =======================================================================

  Future<void> _restoreDebugToggle() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _debugAutoVerify = prefs.getBool('zancrew_debug_auto_verify') ?? false;
    });
  }

  Future<void> _saveDebugToggle(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('zancrew_debug_auto_verify', v);
    setState(() => _debugAutoVerify = v);
  }

  /// Pulls latest verification flags from backend profile
  Future<void> _freshSync() async {
    setState(() => _loading = true);
    try {
      final profile = await ZanCrewApi.getProfile(widget.userId);
      if (!mounted || profile == null) return;

      final st = (profile['status'] as String?) ?? 'pending';

      setState(() {
        _status = st;
        _kycVerified = (profile['kyc_verified'] as bool?) ?? false;
        _bankVerified = (profile['bank_verified'] as bool?) ?? false;
        _aadhaarVerified = (profile['aadhaar_verified'] as bool?) ?? false;
        _selfieVerified = (profile['liveness_verified'] as bool?) ?? false;

        // Automatically open the first incomplete section
        _expandPan = !_kycVerified;
        _expandBank = _kycVerified && !_bankVerified;
        _expandAadhaar = _kycVerified && _bankVerified && !_aadhaarVerified;
        _expandSelfie =
            _kycVerified &&
            _bankVerified &&
            _aadhaarVerified &&
            !_selfieVerified;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // =======================================================================
  // PART 3: SMALL HELPERS (TOAST, BASE64, DOB, VALIDATION GATES)
  // =======================================================================

  void _toast(String msg, {bool ok = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: ok ? _accent : _error,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<String?> _toBase64(File? f) async {
    if (f == null) return null;
    try {
      final bytes = await f.readAsBytes();
      return base64Encode(bytes);
    } catch (_) {
      return null;
    }
  }

  // bool _canPayNow() {
  //   final validForm = _formKey.currentState?.validate() ?? false;
  //   final textOk =
  //       _fullNameCtrl.text.trim().isNotEmpty &&
  //       _panCtrl.text.trim().isNotEmpty &&
  //       _dobCtrl.text.trim().isNotEmpty &&
  //       _accCtrl.text.trim().isNotEmpty &&
  //       _ifscCtrl.text.trim().isNotEmpty;

  //   final imagesOk =
  //       (_aadhaarFrontCropped ?? _aadhaarFront) != null &&
  //       (_aadhaarBackCropped ?? _aadhaarBack) != null &&
  //       (_selfieCropped ?? _selfie) != null;

  //   return validForm && textOk && imagesOk;
  // }

  bool _canPayNow() {
    // ✅ MVP RULE:
    // Allow proceeding once PAN + Bank are verified by backend
    return _kycVerified && _bankVerified;
  }

  // DOB helper
  final _dobInputFormatters = <TextInputFormatter>[
    FilteringTextInputFormatter.allow(RegExp(r'[0-9\-]')),
  ];

  Future<void> _pickDob(BuildContext context) async {
    final now = DateTime.now();
    final latest18 = DateTime(now.year - 18, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 21, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: latest18,
    );
    if (picked == null) return;

    final yyyy = picked.year.toString();
    final mm = picked.month.toString().padLeft(2, '0');
    final dd = picked.day.toString().padLeft(2, '0');
    _dobCtrl.text = '$yyyy-$mm-$dd'; // server expects YYYY-MM-DD
  }

  // =======================================================================
  // PART 4: IMAGE PICKING + OCR
  // =======================================================================

  Future<File?> _cropImage(File file) async {
    try {
      final res = await ImageCropper().cropImage(
        sourcePath: file.path,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 90,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop',
            toolbarColor: _brand,
            toolbarWidgetColor: Colors.white,
            hideBottomControls: true,
            lockAspectRatio: false,
          ),
          IOSUiSettings(title: 'Crop', aspectRatioLockEnabled: false),
        ],
      );
      if (res == null) return null;
      return File(res.path);
    } catch (e) {
      debugPrint('❌ Crop error: $e');
      return null;
    }
  }

  /// Simple camera capture (no OCR)
  Future<void> _pickImage({required bool isFront, bool selfie = false}) async {
    final picked = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 85,
    );
    if (picked == null) return;

    final rawFile = File(picked.path);
    final cropped = await _cropImage(rawFile);

    setState(() {
      if (selfie) {
        _selfie = rawFile;
        _selfieCropped = cropped ?? rawFile;
      } else if (isFront) {
        _aadhaarFront = rawFile;
        _aadhaarFrontCropped = cropped ?? rawFile;
      } else {
        final img = cropped ?? rawFile;
        _aadhaarBack = img;
        _aadhaarBackCropped = img;
      }
    });
  }

  /// Camera + OCR (front) or just capture (back)
  Future<void> _scanAadhaar({required bool front}) async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 90,
      );
      if (picked == null) return;

      File raw = File(picked.path);
      final cropped = await _cropImage(raw);
      final imageFile = cropped ?? raw;

      // FRONT → OCR
      if (front) {
        final inputImage = InputImage.fromFile(imageFile);
        final textRecognizer = TextRecognizer(
          script: TextRecognitionScript.latin,
        );
        final RecognizedText text = await textRecognizer.processImage(
          inputImage,
        );
        await textRecognizer.close();

        final ocrText = text.text;
        debugPrint("🔍 Aadhaar FRONT OCR:\n$ocrText");

        // Extract Aadhaar number (xxxx xxxx xxxx)
        final aadhaarRegex = RegExp(r'\d{4}\s\d{4}\s\d{4}');
        final match = aadhaarRegex.firstMatch(ocrText);
        final aadhaarNum = match?.group(0)?.replaceAll(" ", "");

        // Extract Name + DOB + Gender heuristically
        String? name;
        String? dob;
        String? gender;

        final lines = ocrText.split("\n").map((e) => e.trim()).toList();
        for (final line in lines) {
          final up = line.toUpperCase();

          if (name == null &&
              up.isNotEmpty &&
              RegExp(r'^[A-Z\s\.]+$').hasMatch(up) &&
              !up.contains("GOVERNMENT") &&
              !up.contains("INDIA") &&
              !up.contains("AUTHORITY")) {
            name = line.trim();
          }

          final dobMatch = RegExp(r'\d{4}[\-/]\d{2}[\-/]\d{2}').firstMatch(up);
          if (dobMatch != null) {
            dob = dobMatch.group(0);
          }

          if (gender == null) {
            if (up.contains("MALE")) gender = "Male";
            if (up.contains("FEMALE")) gender = "Female";
          }
        }

        setState(() {
          _aadhaarFront = imageFile;
          _aadhaarFrontCropped = imageFile;

          if (aadhaarNum != null) {
            _aadhaarNumberCtrl.text = aadhaarNum;
          }
          if (name != null && _fullNameCtrl.text.isEmpty) {
            _fullNameCtrl.text = name;
          }
          if (dob != null && _dobCtrl.text.isEmpty) {
            _dobCtrl.text = dob;
          }
        });

        _toast("Front scanned successfully!");
        return;
      }

      // BACK → only store image, no OCR
      setState(() {
        _aadhaarBack = imageFile;
        _aadhaarBackCropped = imageFile;
      });

      debugPrint("📄 Aadhaar BACK captured (no OCR)");
      _toast("Back image captured!");
    } catch (e) {
      debugPrint("❌ Aadhaar OCR error: $e");
      _toast("Scan failed: $e", ok: false);
    }
  }

  // =======================================================================
  // PART 5: INDIVIDUAL VERIFICATION STEPS (PAN, BANK)
  // =======================================================================

  Future<void> _submitPan() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _loading = true);
    try {
      final r = await VerificationApi.startKyc(
        userId: widget.userId,
        pan: _panCtrl.text.trim(),
        fullName: _fullNameCtrl.text.trim(),
        dob: _dobCtrl.text.trim(),
      );

      final ok =
          r['ok'] == true && (r['verified'] == true || r['data'] != null);

      _toast(
        ok ? 'PAN verified successfully' : 'PAN verification failed',
        ok: ok,
      );
      await _freshSync();
    } catch (e) {
      _toast('PAN error: $e', ok: false);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitBank() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _loading = true);
    try {
      final r = await VerificationApi.startBank(
        userId: widget.userId,
        accountNumber: _accCtrl.text.trim(),
        ifsc: _ifscCtrl.text.trim(),
        name: _fullNameCtrl.text.trim(),
      );

      final ok =
          r['ok'] == true && (r['verified'] == true || r['data'] != null);

      _toast(
        ok ? 'Bank verified successfully' : 'Bank verification failed',
        ok: ok,
      );
      await _freshSync();
    } catch (e) {
      _toast('Bank error: $e', ok: false);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // =======================================================================
  // PART 6: UNIFIED VERIFICATION
  // =======================================================================

  Future<void> _runUnifiedVerification() async {
    setState(() => _loading = true);

    try {
      final frontB64 = await _toBase64(_aadhaarFrontCropped ?? _aadhaarFront);
      final backFile = _aadhaarBackCropped ?? _aadhaarBack;
      final backB64 = backFile != null ? await _toBase64(backFile) : null;
      final selfieB64 = await _toBase64(_selfieCropped ?? _selfie);

      debugPrint("====== BASE64 CHECK ======");
      debugPrint(
        "Front present? ${(_aadhaarFrontCropped ?? _aadhaarFront) != null}",
      );
      debugPrint(
        "Back present?  ${_aadhaarBackCropped ?? _aadhaarBack != null}",
      );
      debugPrint("Selfie present? ${_selfieCropped ?? _selfie != null}");
      debugPrint("FrontB64 len: ${frontB64?.length ?? 0}");
      debugPrint("BackB64  len: ${backB64?.length ?? 0}");
      debugPrint("SelfieB64 len: ${selfieB64?.length ?? 0}");

      final payloadPreview = {
        "user_id": widget.userId,
        "pan_number": _panCtrl.text.trim(),
        "full_name": _fullNameCtrl.text.trim(),
        "dob": _dobCtrl.text.trim(),
        "account_number": _accCtrl.text.trim(),
        "ifsc": _ifscCtrl.text.trim(),
        "aadhaar_number": _aadhaarNumberCtrl.text.trim(),
        "aadhaar_front_base64": frontB64 != null
            ? "LOADED(${frontB64.length})"
            : "NULL",
        "aadhaar_back_base64": backB64 != null
            ? "LOADED(${backB64.length})"
            : "NULL",
        "selfie_base64": selfieB64 != null
            ? "LOADED(${selfieB64.length})"
            : "NULL",
      };

      debugPrint("📤 Unified verification payload preview:");
      debugPrint(payloadPreview.toString());

      final result = await VerificationApi.startUnified(
        userId: widget.userId,
        panNumber: _panCtrl.text.trim(),
        fullName: _fullNameCtrl.text.trim(),
        dob: _dobCtrl.text.trim(),
        accountNumber: _accCtrl.text.trim(),
        ifsc: _ifscCtrl.text.trim(),
        aadhaarFrontBase64: frontB64,
        aadhaarBackBase64: backB64,
        selfieBase64: selfieB64,
        aadhaarNumber: _aadhaarNumberCtrl.text.trim().isEmpty
            ? null
            : _aadhaarNumberCtrl.text.trim(),
        debugForceVerifyBodyFlag: _debugAutoVerify,
        debugForceVerifyHeader: _debugAutoVerify,
      );

      if (!mounted) return;

      setState(() => _lastVerification = result);

      await _freshSync();

      final ok = result['ok'] == true;
      // if (ok &&
      //     _kycVerified &&
      //     _bankVerified &&
      //     _aadhaarVerified &&
      //     _selfieVerified) {
      //   _showAndNavigateSuccess();
      // } else {
      //   _toast('Verification failed — see details below', ok: false);
      //   _focusFirstFailedSection(result);
      // }

      if (ok && _kycVerified && _bankVerified) {
        _showAndNavigateSuccess();
      } else {
        _toast('Verification incomplete — see details below', ok: false);
        _focusFirstFailedSection(result);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _lastVerification = {
          'ok': false,
          'step': 'EXCEPTION',
          'error': e.toString(),
        };
      });
      _toast('Verification crashed: $e', ok: false);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _focusFirstFailedSection(Map<String, dynamic> results) {
    final errors = (results['errors'] is List)
        ? List<Map>.from(results['errors'])
        : <Map>[];

    String? firstStep;

    if (errors.isNotEmpty) {
      firstStep = (errors.first['step'] ?? '').toString().toLowerCase();
    } else {
      if (!(results['pan']?['ok'] ?? true)) firstStep ??= 'pan';
      if (!(results['bank']?['ok'] ?? true)) firstStep ??= 'bank';
      if (!(results['aadhaar']?['ok'] ?? true)) firstStep ??= 'aadhaar';
      if (!(results['liveness']?['ok'] ?? true)) firstStep ??= 'selfie';
      if (!(results['face_compare']?['ok'] ?? true)) firstStep ??= 'selfie';
    }

    setState(() {
      _expandPan = firstStep == 'pan';
      _expandBank = firstStep == 'bank';
      _expandAadhaar = firstStep == 'aadhaar' || firstStep == 'ocr';
      _expandSelfie =
          firstStep == 'selfie' ||
          firstStep == 'liveness' ||
          firstStep == 'face match';
    });
  }

  void _showAndNavigateSuccess() {
    setState(() => _showSuccessOverlay = true);

    _successTimer?.cancel();
    _successTimer = Timer(const Duration(milliseconds: 2200), () {
      if (!mounted) return;
      setState(() => _showSuccessOverlay = false);
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ZanCrewDashboard()),
        (route) => false,
      );
    });
  }

  // =======================================================================
  // PART 7: MAIN UI BUILD (MVP — PAN + BANK ONLY)
  // =======================================================================

  @override
  Widget build(BuildContext context) {
    final verifiedCount = [_kycVerified, _bankVerified].where((v) => v).length;

    final progress = verifiedCount / 2.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF7F7FB),
      appBar: AppBar(
        title: const Text('Verification'),
        backgroundColor: _brand,
        elevation: 0,
      ),
      body: Stack(
        children: [
          Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                _headerCard(progress),
                const SizedBox(height: 12),

                // 1) PAN
                _accordionCard(
                  title: '1. PAN Verification',
                  verified: _kycVerified,
                  expanded: _expandPan,
                  onToggle: () => setState(() => _expandPan = !_expandPan),
                  children: [
                    _input(
                      'Full Name (as per PAN)',
                      _fullNameCtrl,
                      validator: _req,
                      textCapitalization: TextCapitalization.words,
                    ),
                    _input(
                      'PAN Number',
                      _panCtrl,
                      validator: _reqPan,
                      textCapitalization: TextCapitalization.characters,
                    ),
                    _input(
                      'Date of Birth (YYYY-MM-DD)',
                      _dobCtrl,
                      keyboardType: TextInputType.text,
                      inputFormatters: _dobInputFormatters,
                      validator: _reqDob,
                      suffix: IconButton(
                        icon: const Icon(Icons.calendar_month),
                        onPressed: () => _pickDob(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _primaryButton(
                      label: 'Verify PAN',
                      onPressed: _loading ? null : _submitPan,
                    ),
                  ],
                ),

                // 2) Bank
                _accordionCard(
                  title: '2. Bank Verification',
                  verified: _bankVerified,
                  expanded: _expandBank,
                  onToggle: () => setState(() => _expandBank = !_expandBank),
                  children: [
                    _input(
                      'Account Number',
                      _accCtrl,
                      validator: _req,
                      keyboardType: TextInputType.number,
                    ),
                    _input(
                      'IFSC Code',
                      _ifscCtrl,
                      validator: _reqIfsc,
                      textCapitalization: TextCapitalization.characters,
                    ),
                    const SizedBox(height: 8),
                    _primaryButton(
                      label: 'Verify Bank',
                      onPressed: _loading ? null : _submitBank,
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                // ✅ MVP FINAL ACTION
                _primaryButton(
                  label: 'Verify & Continue',
                  onPressed: _loading
                      ? null
                      : (_canPayNow() ? _runUnifiedVerification : null),
                ),

                const SizedBox(height: 12),
                const Center(
                  child: Text(
                    'Continue once PAN and Bank are verified',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ),

                const SizedBox(height: 20),

                if (_lastVerification != null) _resultCard(_lastVerification!),

                const SizedBox(height: 28),
                _disclaimerCard(),
              ],
            ),
          ),

          if (_showSuccessOverlay) _successOverlay(),

          if (_loading)
            Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  // =======================================================================
  // PART 8: SMALL WIDGET BUILDERS
  // =======================================================================

  Widget _headerCard(double progress) {
    final pct = (progress * 100).round();
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _brand.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.verified_user, color: _brand),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Get verified to start earning',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                        ),
                      ),
                      Text(
                        'Status: ${_status.toUpperCase()}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: Colors.grey.shade200,
                valueColor: AlwaysStoppedAnimation(
                  progress < 1 ? Colors.orangeAccent : _accent,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$pct% complete',
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
      ),
    );
  }

  Widget _debugPanel() {
    return Card(
      color: Colors.orange[50],
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.build_rounded, color: Colors.orange),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                '🛠 DEBUG: Auto-Verify (backend bypass)\nTurns on mock verification for Aadhaar/Selfie via backend.',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            Switch(
              value: _debugAutoVerify,
              onChanged: (v) async {
                await _saveDebugToggle(v);
                _toast(
                  v ? 'Debug auto-verify ON' : 'Debug auto-verify OFF',
                  ok: true,
                );
              },
              activeColor: Colors.orange,
            ),
          ],
        ),
      ),
    );
  }

  Widget _accordionCard({
    required String title,
    required bool verified,
    required bool expanded,
    required VoidCallback onToggle,
    required List<Widget> children,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                verified ? Icons.verified : Icons.edit_note,
                color: verified ? _accent : _brand,
              ),
              title: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              trailing: Icon(expanded ? Icons.expand_less : Icons.expand_more),
              onTap: onToggle,
            ),
            if (expanded) ...[
              const Divider(height: 10),
              const SizedBox(height: 6),
              ...children,
            ],
          ],
        ),
      ),
    );
  }

  Widget _input(
    String label,
    TextEditingController ctrl, {
    TextInputType? keyboardType,
    TextCapitalization textCapitalization = TextCapitalization.none,
    String? Function(String?)? validator,
    List<TextInputFormatter>? inputFormatters,
    Widget? suffix,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: ctrl,
        keyboardType: keyboardType,
        textCapitalization: textCapitalization,
        validator: validator,
        inputFormatters: inputFormatters,
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: const Color(0xFFF8F8FF),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: _brand, width: 1.6),
          ),
          suffixIcon: suffix,
        ),
      ),
    );
  }

  Widget _captureTile(
    String label,
    File? file,
    VoidCallback onCapture, {
    String? hint,
    List<Widget> extraActions = const [],
  }) {
    return InkWell(
      onTap: onCapture,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 170,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.grey.shade300),
          color: Colors.white,
          image: file != null
              ? DecorationImage(image: FileImage(file), fit: BoxFit.cover)
              : null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: file == null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.camera_alt_outlined,
                      color: _brand,
                      size: 28,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      label,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (hint != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        hint,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.black54,
                        ),
                      ),
                    ],
                    if (extraActions.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(spacing: 6, runSpacing: 6, children: extraActions),
                    ],
                  ],
                ),
              )
            : Stack(
                children: [
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Container(
                      margin: const EdgeInsets.all(8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.photo, color: Colors.white, size: 16),
                          SizedBox(width: 6),
                          Text(
                            'Captured',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 6,
                    right: 6,
                    child: InkWell(
                      onTap: () => setState(() {
                        final l = label.toLowerCase();
                        if (l.contains('front')) {
                          _aadhaarFront = null;
                          _aadhaarFrontCropped = null;
                        } else if (l.contains('back')) {
                          _aadhaarBack = null;
                          _aadhaarBackCropped = null;
                        } else if (l.contains('selfie')) {
                          _selfie = null;
                          _selfieCropped = null;
                        }
                      }),
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.35),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.all(4),
                        child: const Icon(
                          Icons.close,
                          size: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: Row(
                      children: [
                        _miniBtn('Crop', () async {
                          File? base;
                          final l = label.toLowerCase();
                          if (l.contains('front')) base = _aadhaarFront;
                          if (l.contains('back')) base = _aadhaarBack;
                          if (l.contains('selfie')) base = _selfie;
                          if (base == null) return;

                          final c = await _cropImage(base);
                          setState(() {
                            if (l.contains('front')) {
                              _aadhaarFrontCropped = c ?? base;
                            } else if (l.contains('back')) {
                              _aadhaarBackCropped = c ?? base;
                            } else {
                              _selfieCropped = c ?? base;
                            }
                          });
                        }),
                        const SizedBox(width: 6),
                        ...extraActions,
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _miniBtn(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(6),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _primaryButton({required String label, VoidCallback? onPressed}) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: onPressed == null ? Colors.grey.shade300 : _brand,
          disabledBackgroundColor: Colors.grey.shade300,
          elevation: onPressed == null ? 0 : 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: onPressed == null ? Colors.black45 : Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  Widget _okHint(String msg) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: _accent, size: 18),
          const SizedBox(width: 6),
          Text(msg, style: const TextStyle(color: _ink)),
        ],
      ),
    );
  }

  Widget _warnHint(String msg) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Colors.orange, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Text(msg, style: const TextStyle(color: _ink)),
          ),
        ],
      ),
    );
  }

  Widget _resultCard(Map<String, dynamic> results) {
    final ok = results['ok'] == true;
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 0,
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  ok ? Icons.verified : Icons.report_gmailerrorred_outlined,
                  color: ok ? _accent : _error,
                ),
                const SizedBox(width: 8),
                Text(
                  ok ? 'All verification steps passed' : 'Verification result',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (!ok) _numberedFailureList(results),
          ],
        ),
      ),
    );
  }

  Widget _numberedFailureList(Map<String, dynamic> results) {
    final issues = _collectIssues(results);
    if (issues.isEmpty) {
      return const Text(
        'No detailed errors provided.',
        style: TextStyle(color: Colors.black54),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < issues.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: _error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: _error,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 14,
                        height: 1.3,
                      ),
                      children: [
                        TextSpan(
                          text: '${issues[i].step} ',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const TextSpan(text: '→ '),
                        TextSpan(text: issues[i].reason),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  List<_StepIssue> _collectIssues(Map<String, dynamic> results) {
    final List<_StepIssue> out = [];

    if (results['errors'] is List) {
      for (final e in results['errors']) {
        final step = (e['step'] ?? 'Unknown').toString();
        final reason = (e['reason'] ?? 'Verification failed').toString();
        out.add(_StepIssue(step: step, reason: reason));
      }
      return out;
    }

    void addIfFailed(String title, dynamic v, String fb) {
      if (v is Map && v['ok'] != true) {
        final msg = (v['error'] is Map && v['error']['message'] != null)
            ? v['error']['message'].toString()
            : (v['error']?.toString() ?? fb);
        out.add(_StepIssue(step: title, reason: msg));
      }
    }

    addIfFailed('PAN Verification', results['pan'], 'PAN verification failed');
    addIfFailed(
      'Bank Verification',
      results['bank'],
      'Bank verification failed',
    );
    addIfFailed(
      'Aadhaar OCR',
      results['aadhaar'],
      'Aadhaar verification failed',
    );
    addIfFailed('Liveness', results['liveness'], 'Selfie liveness failed');
    addIfFailed('Face Match', results['face_compare'], 'Face match failed');

    return out;
  }

  Widget _successOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.50),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(22),
          width: 260,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.verified, color: _accent, size: 52),
              SizedBox(height: 12),
              Text(
                'Verified successfully!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 6),
              Text(
                'Taking you to your dashboard…',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.black54),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _disclaimerCard() {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Transform.rotate(
              angle: -math.pi / 20,
              child: const Icon(
                Icons.privacy_tip_outlined,
                color: Colors.black54,
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Your documents are encrypted in transit. We only store minimal '
                'verification flags and last-4 where required for compliance.',
                style: TextStyle(
                  color: Colors.black87,
                  fontSize: 12,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =======================================================================
  // PART 9: VALIDATORS
  // =======================================================================

  String? _req(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  String? _reqPan(String? v) {
    final t = v?.trim().toUpperCase() ?? '';
    if (t.isEmpty) return 'Required';
    final rgx = RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$');
    return rgx.hasMatch(t) ? null : 'Invalid PAN format';
  }

  String? _reqDob(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return 'Required';
    final rgx = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (!rgx.hasMatch(t)) return 'Use YYYY-MM-DD';
    final dob = DateTime.tryParse(t);
    if (dob == null) return 'Invalid date';
    final now = DateTime.now();
    final age = now.year - dob.year -
        ((now.month < dob.month ||
                (now.month == dob.month && now.day < dob.day))
            ? 1
            : 0);
    if (age < 18) return 'Must be 18 or older';
    return null;
  }

  String? _reqIfsc(String? v) {
    final t = v?.trim().toUpperCase() ?? '';
    if (t.isEmpty) return 'Required';
    final rgx = RegExp(r'^[A-Z]{4}0[0-9A-Z]{6}$');
    return rgx.hasMatch(t) ? null : 'Invalid IFSC';
  }

  String? _optAadhaar(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return null;
    final rgx = RegExp(r'^\d{12}$');
    return rgx.hasMatch(t) ? null : 'Must be 12 digits';
  }
}

class _StepIssue {
  final String step;
  final String reason;

  _StepIssue({required this.step, required this.reason});
}
