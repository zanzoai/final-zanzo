// This file powers the main Home screen:
// - Handles voice recording, typed input, task submission
// - Shows dynamic examples ticker
// - Loads user info + ZanCrew status
// - Navigates to Profile, ReviewTask, and Earn flows

// lib/features/common/home/home_screen.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Core
import 'package:zanzo_frontend/core/services/api_service.dart';
import 'package:zanzo_frontend/core/services/auth.dart';
import 'package:zanzo_frontend/core/services/voice_ws_service.dart';
import 'package:zanzo_frontend/core/services/zancrew_api.dart';
// User feature
import 'package:zanzo_frontend/features/user/screens/profile_screen.dart';
import 'package:zanzo_frontend/features/user/screens/review_task_screen.dart';
import 'package:zanzo_frontend/features/user/widgets/login_prompt_dialog.dart';
// ZanCrew
import 'package:zanzo_frontend/features/zancrew/gateway/zancrew_gateway.dart';
import 'package:zanzo_frontend/features/zancrew/screens/zancrew_JobDetails.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  // ---------------------------------------------------------------------------
  // INPUT + RESPONSE
  // ---------------------------------------------------------------------------

  final TextEditingController _controller = TextEditingController();
  bool _isLoading = false;
  String? _policyMessage;
  String _response = "";

  // ---------------------------------------------------------------------------
  // VOICE SERVICE
  // ---------------------------------------------------------------------------

  late final VoiceWsService _voice = VoiceWsService();

  // ---------------------------------------------------------------------------
  // USER / PREFS
  // ---------------------------------------------------------------------------

  String? _userName;
  String? _userPhone;

  // ---------------------------------------------------------------------------
  // ZANCREW STATUS (top-left Work icon)
  // ---------------------------------------------------------------------------

  String _zancrewStatus = 'off'; // off | pending | active | rejected
  bool _zancrewEnabled = false;

  // ---------------------------------------------------------------------------
  // ACTIVE JOB CTA (bottom floating card)
  // ---------------------------------------------------------------------------

  String? _activeJobId;
  String? _activeJobTitle;
  String? _activeJobStatus;

  // ---------------------------------------------------------------------------
  // ANIMATIONS (glow shadow around input box)
  // ---------------------------------------------------------------------------

  late final AnimationController _glowCtrl = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  )..repeat(reverse: true);

  late final Animation<double> _glowAnim = CurvedAnimation(
    parent: _glowCtrl,
    curve: Curves.easeInOut,
  );

  // ---------------------------------------------------------------------------
  // EXAMPLES TICKER (auto-type examples)
  // ---------------------------------------------------------------------------

  final List<_Example> _examples = const [
    _Example(
      emoji: '📦',
      name: 'Ramya',
      text:
          'Wait at my flat for fridge delivery, take photos, and place it in the kitchen.',
    ),
    _Example(
      emoji: '🛠️',
      name: 'Ramesh',
      text:
          'Supervise the plumber and confirm the leak is fixed with before/after photos.',
    ),
    _Example(
      emoji: '📱',
      name: 'Isha',
      text:
          'Collect my repaired phone from the service center and drop it at my office.',
    ),
    _Example(
      emoji: '🪔',
      name: 'Tanvi',
      text:
          'Set up for a small pooja—arrange flowers, stools, and tidy up after.',
    ),
    _Example(
      emoji: '📄',
      name: 'Nisha',
      text:
          'Hold my spot in the bank queue, submit the form, and send receipt photos.',
    ),
    _Example(
      emoji: '🔑',
      name: 'Rohit',
      text:
          'Key handover to a new tenant—verify ID and note electricity meter reading.',
    ),
    _Example(
      emoji: '🌐',
      name: 'Lalita',
      text:
          'Wait for broadband installation (3–5 PM), test speed, and save technician contact.',
    ),
    _Example(
      emoji: '📸',
      name: 'Vikram',
      text: 'Take 10 clear photos of my vacant flat for property listing.',
    ),
    _Example(
      emoji: '📝',
      name: 'Akhil',
      text:
          'Collect documents from the society office and drop them at my lawyer’s.',
    ),
  ];

  int _exIndex = 0;
  String _typed = '';
  Timer? _typeTimer;
  Timer? _holdTimer;

  // ---------------------------------------------------------------------------
  // INIT
  // ---------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();
    _registerFcmTokenIfLoggedIn();
    _loadUser();
    _loadZancrewFromPrefs();
    _backgroundSyncZanCrew();
    _checkActiveJob();
    _startTicker();

    // Sync UI with mic events
    _controller.addListener(() => setState(() {}));

    // Voice → append final text only (manual-final mode)
    _voice.addListener(() {
      if (!mounted) return;

      if (!_voice.isRecording &&
          !_voice.isTranscribing &&
          _voice.finalText.trim().isNotEmpty) {
        final spoken = _voice.finalText.trim();
        final existing = _controller.text.trim();

        _controller.text = existing.isEmpty ? spoken : "$existing $spoken";

        _controller.selection = TextSelection.fromPosition(
          TextPosition(offset: _controller.text.length),
        );

        _voice.clearText(); // avoid re-append
      }
      setState(() {});
    });
  }

  @override
  void dispose() {
    _typeTimer?.cancel();
    _holdTimer?.cancel();
    _glowCtrl.dispose();
    _controller.dispose();
    _voice.disposeAll();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // LOAD USER FROM PREFS
  // ---------------------------------------------------------------------------

  Future<void> _registerFcmTokenIfLoggedIn() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final accessToken = prefs.getString('access_token');
      if (accessToken == null || accessToken.isEmpty) return;
      final token = await FirebaseMessaging.instance.getToken();
      if (token == null) return;
      final platform = Platform.isIOS ? 'ios' : 'android';
      await ApiService.registerDeviceToken(token: token, platform: platform);
    } catch (e) {
      debugPrint('[FCM] customer token registration error: $e');
    }
  }

  Future<void> _loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _userName = prefs.getString('user_name');
      _userPhone = prefs.getString('user_phone');
    });
  }

  // ---------------------------------------------------------------------------
  // LOAD ZANCREW STATUS FROM PREFS
  // ---------------------------------------------------------------------------

  Future<void> _loadZancrewFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _zancrewStatus = prefs.getString('zancrew_status') ?? 'off';
      _zancrewEnabled = prefs.getBool('zancrew_enabled') ?? false;
    });
  }

  // ---------------------------------------------------------------------------
  // BACKGROUND SYNC — KEEP ZANCREW STATUS FRESH
  // ---------------------------------------------------------------------------

  Future<void> _backgroundSyncZanCrew() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');
    if (userId == null) return;

    try {
      final profile = await ZanCrewApi.getProfile(userId);
      if (profile == null) return;

      final status = (profile['status'] as String?) ?? 'pending';
      final active = status == 'active';

      await prefs.setString('zancrew_status', status);
      await prefs.setBool('zancrew_enabled', active);

      if (!mounted) return;

      setState(() {
        _zancrewStatus = status;
        _zancrewEnabled = active;
      });
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // ACTIVE JOB CHECK
  // ---------------------------------------------------------------------------

  Future<void> _checkActiveJob() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id') ?? '';
    if (userId.isEmpty) return;
    try {
      final res = await ApiService.getJson(
        '/zancrew/active_task',
      );
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map && data['active'] == true) {
          setState(() {
            _activeJobId = (data['task_id'] ?? data['job_id'])?.toString();
            _activeJobTitle = data['task_title']?.toString();
            _activeJobStatus = data['status']?.toString();
          });
          return;
        }
      }
    } catch (_) {}
    // 404 or any error: no active job
    if (mounted) {
      setState(() {
        _activeJobId = null;
        _activeJobTitle = null;
        _activeJobStatus = null;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // VOICE TOGGLE
  // ---------------------------------------------------------------------------

  Future<void> _toggleVoice() async {
    if (_voice.isRecording) {
      await _voice.stop(); // triggers transcribing & append later
      setState(() {});
      return;
    }
    await _voice.start();
    setState(() {});
  }

  // ---------------------------------------------------------------------------
  // SUBMIT TASK → /process_task
  // ---------------------------------------------------------------------------

  Future<void> _sendRequest() async {
    final userInput = _controller.text.trim();
    if (userInput.isEmpty) return;

    // Require login before hitting any authenticated endpoint.
    final signedIn = await Auth.requireSignIn(context);
    if (!signedIn || !mounted) return;

    setState(() {
      _isLoading = true;
      _response = '';
      _policyMessage = null;
    });

    try {
      // ── Location guard ────────────────────────────────────────────────────
      Position? pos;
      try {
        bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) throw Exception('location_service_disabled');

        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
        }
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          throw Exception('location_permission_denied');
        }

        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
        ).timeout(const Duration(seconds: 8));
      } catch (locErr) {
        // ignore: avoid_print
        print('[Home] Location error: $locErr');

        // Set to true only when intentionally testing locally without a GPS fix.
        // Must remain false for any real device or production testing.
        // ignore: dead_code
        const bool allowZeroCoordsForLocalDev = false;

        // ignore: dead_code
        if (allowZeroCoordsForLocalDev) {
          // ignore: avoid_print
          print(
            '[Home] DEV OVERRIDE: falling back to 0.0,0.0 for local testing',
          );
        } else {
          if (!mounted) return;
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Location is needed to find nearby ZanCrew. '
                'Please enable location permission and try again.',
              ),
              duration: Duration(seconds: 4),
            ),
          );
          return;
        }
      }

      // ignore: avoid_print
      print(
        '[Home] → calling ApiService.processTask lat=${pos?.latitude ?? 0.0} lng=${pos?.longitude ?? 0.0}',
      );
      final data = await ApiService.processTask(
        userInput: userInput,
        latitude: pos?.latitude ?? 0.0,
        longitude: pos?.longitude ?? 0.0,
      );
      // ignore: avoid_print
      print('[Home] ← ApiService.processTask returned: $data');

      if (!mounted) return;

      // ⭐ NEW: policy-specific friendly messages
      if (data != null && data['ok'] == false) {
        final type = data['error_type']?.toString() ?? '';
        String msg =
            data['user_message']?.toString() ??
            "We can't help with that request.";

        if (type == 'adult') {
          msg = "We can’t assist with adult, intimate, or inappropriate tasks.";
        } else if (type == 'illegal') {
          msg =
              "We can’t support anything illegal or risky. Please try another task.";
        } else if (type == 'dangerous') {
          msg = "We can’t help with tasks involving danger, weapons, or harm.";
        } else if (type == 'scam') {
          msg =
              "This request appears unsafe or deceptive. Please try another one.";
        } else if (type == 'medical') {
          msg = "We can’t provide medical or health-risk related tasks.";
        } else if (type == 'nonsense') {
          msg = "Tell us a clear task you need help with—try again.";
        } else if (type == 'personal_services') {
          msg =
              "We can’t assist with intimate or personal companionship tasks.";
        } else if (type == 'too_vague') {
          msg = "Please describe your task more clearly so we can help.";
        }

        setState(() {
          _policyMessage = msg;
          _isLoading = false;
        });
        return;
      }

      // ⭐ NORMAL SUCCESS → NAVIGATE TO REVIEW SCREEN
      if (data != null &&
          data['task_type'] != null &&
          data['task_detail'] != null &&
          data['task_detail']['polished_task'] != null) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ReviewTaskScreen(
              taskType: data['task_type'] as String,
              taskDetail: Map<String, dynamic>.from(data['task_detail'] as Map),
            ),
          ),
        );
      } else {
        setState(() {
          _response = "Server returned incomplete or invalid data.";
        });
      }
    } catch (e) {
      // ignore: avoid_print
      print('[Home] _sendRequest error: $e');
      if (!mounted) return;
      setState(() {
        _response =
            "Sorry, we couldn't understand your request. Please try again.";
      });
    }

    if (mounted) setState(() => _isLoading = false);
  }

  // ---------------------------------------------------------------------------
  // PROFILE TAP
  // ---------------------------------------------------------------------------

  Future<void> _onAvatarTap() async {
    if (_userName == null || _userPhone == null) {
      final ok = await showLoginPrompt(context);
      if (!ok) return;
      await _loadUser();
    }

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
  }

  String get _avatarInitial {
    final n = _userName?.trim();
    if (n == null || n.isEmpty) return 'Y';
    return n[0].toUpperCase();
  }

  // ---------------------------------------------------------------------------
  // EXAMPLES TICKER — TYPEWRITER EFFECT
  // ---------------------------------------------------------------------------

  void _startTicker() => _setExample(0);

  void _setExample(int idx) {
    _typeTimer?.cancel();
    _holdTimer?.cancel();

    _exIndex = idx % _examples.length;
    _typed = '';
    final full = _examples[_exIndex].text;

    _typeTimer = Timer.periodic(const Duration(milliseconds: 26), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }

      if (_typed.length < full.length) {
        setState(() => _typed = full.substring(0, _typed.length + 1));
      } else {
        t.cancel();
        _holdTimer = Timer(const Duration(milliseconds: 1600), () {
          if (!mounted) return;
          _setExample((_exIndex + 1) % _examples.length);
        });
      }
    });

    setState(() {});
  }

  void _onExampleTap() {
    final text = _examples[_exIndex].text;
    _controller.text = text;
    _controller.selection = TextSelection.fromPosition(
      TextPosition(offset: _controller.text.length),
    );
    setState(() {});
  }

  // ---------------------------------------------------------------------------
  // EARN BUTTON → ZANCrew GATEWAY
  // ---------------------------------------------------------------------------

  Future<void> _onTapEarn() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id');

    if (userId == null) {
      if (!mounted) return;
      final ok = await showLoginPrompt(context);
      if (!ok) return;
    }

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ZanCrewGateway()),
    );
    _checkActiveJob();
  }

  // ---------------------------------------------------------------------------
  // BUILD UI (PART 2 COMING NEXT)
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final canSend = _controller.text.trim().isNotEmpty && !_isLoading;
    final shadowLevel = 0.06 + (_glowAnim.value * 0.05);
    final isTyping = _controller.text.trim().isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0),
          child: Stack(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 56),
                  const Text(
                    "Zanzo",
                    style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "Thoughts into Action",
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),

                  const Spacer(flex: 2),

                  const Text(
                    "Hire a human near you",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Describe what you need—Zanzo turns it into action.",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 15, color: Colors.grey),
                  ),
                  const SizedBox(height: 18),

                  // -----------------------------------------------------------
                  // INPUT CARD (type or speak)
                  // -----------------------------------------------------------
                  AnimatedBuilder(
                    animation: _glowAnim,
                    builder: (context, _) {
                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.grey[50],
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: Colors.grey.shade200),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(shadowLevel),
                              blurRadius: 14 + (8 * _glowAnim.value),
                              spreadRadius: 0.5 + (0.5 * _glowAnim.value),
                              offset: Offset(0, 3 + (2 * _glowAnim.value)),
                            ),
                          ],
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _MicButton(
                              isRecording: _voice.isRecording,
                              isTranscribing: _voice.isTranscribing,
                              onPressed: _toggleVoice,
                            ),

                            Expanded(
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  minHeight: 56,
                                  maxHeight: 180,
                                ),
                                child: Scrollbar(
                                  child: TextField(
                                    controller: _controller,
                                    onChanged: (_) => setState(() {}),
                                    onSubmitted: (_) =>
                                        canSend ? _sendRequest() : null,
                                    minLines: 3,
                                    maxLines: 6,
                                    keyboardType: TextInputType.multiline,
                                    textInputAction: TextInputAction.newline,
                                    decoration: const InputDecoration(
                                      hintText: "Type or speak your request…",
                                      border: InputBorder.none,
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            IconButton(
                              icon: const Icon(Icons.arrow_upward_rounded),
                              onPressed: canSend ? _sendRequest : null,
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  const SizedBox(height: 16),

                  // -----------------------------------------------------------
                  // SAFETY MESSAGE (only when ok=false)
                  // -----------------------------------------------------------
                  if (_policyMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 6),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.red.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.info_outline_rounded,
                              color: Colors.red,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _policyMessage!,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Colors.red,
                                  height: 1.3,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // -----------------------------------------------------------
                  // EXAMPLES (hide while typing)
                  // -----------------------------------------------------------
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: isTyping
                        ? const SizedBox.shrink()
                        : Column(
                            key: const ValueKey('examples'),
                            children: [
                              GestureDetector(
                                onTap: _onExampleTap,
                                behavior: HitTestBehavior.opaque,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 8,
                                  ),
                                  child: Row(
                                    children: [
                                      Text(
                                        '${_examples[_exIndex].name} · ${_examples[_exIndex].emoji}  ',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.grey.shade800,
                                        ),
                                      ),
                                      Expanded(
                                        child: Text(
                                          _typed.isEmpty
                                              ? '"${_examples[_exIndex].text}"'
                                              : '"$_typed"',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: Colors.grey.shade700,
                                            height: 1.25,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              const SizedBox(height: 4),

                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(_examples.length, (i) {
                                  final active = i == _exIndex;
                                  return Container(
                                    width: active ? 10 : 6,
                                    height: 6,
                                    margin: const EdgeInsets.symmetric(
                                      horizontal: 3,
                                    ),
                                    decoration: BoxDecoration(
                                      color: active
                                          ? Colors.black87
                                          : Colors.grey.shade400,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  );
                                }),
                              ),
                            ],
                          ),
                  ),

                  if (_voice.isRecording || _voice.isTranscribing)
                    const SizedBox(height: 10),

                  if (_isLoading)
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: CircularProgressIndicator(strokeWidth: 2.6),
                    ),

                  if (_response.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _response,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                    ),

                  const Spacer(flex: 3),
                ],
              ),

              // -----------------------------------------------------------
              // EARN BUTTON (top-left)
              // -----------------------------------------------------------
              Positioned(
                top: 0,
                left: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4.0, top: 4.0),
                    child: IconButton(
                      tooltip: 'Earn with Zanzo',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      iconSize: 22,
                      color: _zancrewStatus == 'active'
                          ? Colors.green
                          : Colors.grey.shade800,
                      icon: const Icon(Icons.work_outline_rounded),
                      onPressed: _onTapEarn,
                    ),
                  ),
                ),
              ),

              // -----------------------------------------------------------
              // AVATAR BUTTON (top-right)
              // -----------------------------------------------------------
              Positioned(
                top: 10,
                right: 0,
                child: GestureDetector(
                  onTap: _onAvatarTap,
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.grey.shade200,
                    child: Text(
                      _avatarInitial,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ),

              // -----------------------------------------------------------
              // ACTIVE JOB CTA (bottom floating card, hidden when keyboard open)
              // -----------------------------------------------------------
              if (_activeJobId != null &&
                  MediaQuery.of(context).viewInsets.bottom == 0)
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: _ActiveJobBanner(
                    taskTitle: _activeJobTitle,
                    rawStatus: _activeJobStatus,
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CrewJobDetail(jobId: _activeJobId!),
                        ),
                      );
                      _checkActiveJob();
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// SMALL UI PIECES
// ===========================================================================

class _MicButton extends StatelessWidget {
  final bool isRecording;
  final bool isTranscribing;
  final VoidCallback onPressed;

  const _MicButton({
    required this.isRecording,
    required this.isTranscribing,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final showListening = isRecording;
    final showTranscribing = !isRecording && isTranscribing;

    return Padding(
      padding: const EdgeInsets.only(right: 6.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              isRecording ? Icons.stop_circle_rounded : Icons.mic_none_rounded,
              color: isRecording ? Colors.red : Colors.black87,
              size: 28,
            ),
            onPressed: onPressed,
          ),

          if (showListening)
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: _Pill(text: "Listening…", color: Colors.red),
            ),

          if (showTranscribing)
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: _Pill(text: "Transcribing…", color: Colors.black87),
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;

  const _Pill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// Simple model for examples
class _Example {
  final String name;
  final String emoji;
  final String text;

  const _Example({required this.name, required this.emoji, required this.text});
}

// ===========================================================================
// ACTIVE JOB BANNER — bottom floating CTA shown when crew has an active job
// ===========================================================================

class _ActiveJobBanner extends StatelessWidget {
  final String? taskTitle;
  final String? rawStatus;
  final VoidCallback onTap;

  const _ActiveJobBanner({
    required this.taskTitle,
    required this.rawStatus,
    required this.onTap,
  });

  String get _statusLabel {
    switch (rawStatus) {
      case 'assigned':
        return 'Assigned';
      case 'travelling':
        return 'Travelling';
      case 'arrived':
        return 'Arrived';
      case 'in_progress':
        return 'In progress';
      default:
        return rawStatus ?? '';
    }
  }

  String? get _nextStep {
    switch (rawStatus) {
      case 'assigned':
        return 'Next: Head to location';
      case 'travelling':
        return 'Next: Mark arrived';
      case 'arrived':
        return 'Next: Start job';
      case 'in_progress':
        return 'Next: Complete job';
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = _statusLabel;
    final nextStep = _nextStep;
    final hasTitle = taskTitle != null && taskTitle!.isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.fromLTRB(0, 0, 0, 8),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.18),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ROW 1: green dot + "On duty now" + status pill
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: Color(0xFF4ADE80),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'On duty now',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    letterSpacing: -0.2,
                  ),
                ),
                const Spacer(),
                if (label.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
              ],
            ),

            // ROW 2: job title
            if (hasTitle) ...[
              const SizedBox(height: 5),
              Text(
                taskTitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.75),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],

            // ROW 3: next-step hint
            if (nextStep != null) ...[
              const SizedBox(height: 3),
              Text(
                nextStep,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.4),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],

            // ROW 4: return CTA
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Return →',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
