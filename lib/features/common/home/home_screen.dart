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
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Core
import 'package:zanzo_frontend/core/services/api_service.dart';
import 'package:zanzo_frontend/core/services/auth.dart';
import 'package:zanzo_frontend/core/services/speech_service.dart';
import 'package:zanzo_frontend/core/services/zancrew_api.dart';
// User feature
import 'package:zanzo_frontend/features/user/screens/profile_screen.dart';
import 'package:zanzo_frontend/features/user/screens/review_task_screen.dart';
import 'package:zanzo_frontend/features/user/widgets/login_prompt_dialog.dart';
// ZanCrew
import 'package:zanzo_frontend/features/zancrew/gateway/zancrew_gateway.dart';
import 'package:zanzo_frontend/features/zancrew/screens/zancrew_JobDetails.dart';

// Design tokens — scoped to this file
const _kGround = Color(0xFFFCFAF6);
const _kInk = Color(0xFF26211C);
const _kSaffron = Color(0xFFD97706);
const _kMuted = Color(0xFF8C8378);

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

  late final SpeechService _voice = SpeechService();

  // Stable snapshot of the text box taken when mic is tapped.
  // Never mutated by the listener mid-session; every partial/final callback
  // merges against this same base so append always works correctly.
  String _voiceBaseText = '';

  // Fires every second while long dictation is active to refresh the countdown.
  Timer? _countdownTimer;

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
  // EXAMPLES TICKER — UK-relevant tasks, global names
  // ---------------------------------------------------------------------------

  final List<_Example> _examples = const [
    _Example(
      emoji: '📦',
      name: 'Emma',
      text: 'Pick up my parcel from the post office and bring it to my flat.',
    ),
    _Example(
      emoji: '🛒',
      name: 'John',
      text: 'Buy groceries from Tesco and deliver them to my address.',
    ),
    _Example(
      emoji: '🛋️',
      name: 'Maya',
      text: 'Wait at my flat for a sofa delivery and let the team in.',
    ),
    _Example(
      emoji: '📦',
      name: 'Oliver',
      text: 'Help carry two heavy boxes up two flights of stairs.',
    ),
    _Example(
      emoji: '📄',
      name: 'Sophie',
      text: 'Collect documents from a nearby office and drop them here.',
    ),
    _Example(
      emoji: '🔑',
      name: 'Daniel',
      text:
          'Key handover to a new tenant — verify ID and note the meter reading.',
    ),
    _Example(
      emoji: '📶',
      name: 'Grace',
      text: 'Wait for the broadband engineer (9–12 PM) and confirm it works.',
    ),
    _Example(
      emoji: '📸',
      name: 'Noah',
      text: 'Take 10 clear photos of my vacant flat for a property listing.',
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

    // Voice listener — three-branch session model:
    //
    //  1. isRecording + partialText  → live preview (base + partial)
    //  2. !isRecording + finalText   → authoritative commit; clear base
    //  3. !isRecording + partialText → status-'done' preview; KEEP base so that
    //                                   _onResult(final), which fires a moment
    //                                   later on iOS, can still merge correctly
    //  4. !isRecording + both empty  → nothing heard; restore pre-session text
    _voice.addListener(() {
      if (!mounted) return;

      if (_voice.isRecording) {
        // Live partial preview while the mic is open.
        if (_voice.partialText.isNotEmpty) {
          final base = _voiceBaseText.trim();
          _controller.text = base.isEmpty
              ? _voice.partialText
              : '$base ${_voice.partialText}';
          _controller.selection = TextSelection.fromPosition(
            TextPosition(offset: _controller.text.length),
          );
        }
      } else {
        if (_voice.finalText.trim().isNotEmpty) {
          // Authoritative final result — commit and end the session.
          // Clear _voiceBaseText BEFORE clearText() so the re-entrant
          // notifyListeners() call inside clearText() sees an empty base
          // and doesn't hit the restore branch below.
          _stopCountdownTimer();
          final base = _voiceBaseText.trim();
          final spoken = _voice.finalText.trim();
          _voiceBaseText = '';
          _controller.text = base.isEmpty ? spoken : '$base $spoken';
          _controller.selection = TextSelection.fromPosition(
            TextPosition(offset: _controller.text.length),
          );
          _voice.clearText();
        } else if (_voice.partialText.trim().isNotEmpty) {
          // _onStatus('done') fired but _onResult(final) has not arrived yet
          // (common on iOS: status fires first, final follows ~50–200 ms later).
          // Show the merged text as a live preview but do NOT commit or clear
          // _voiceBaseText — we need it intact for the upcoming _onResult.
          final base = _voiceBaseText.trim();
          final partial = _voice.partialText.trim();
          _controller.text = base.isEmpty ? partial : '$base $partial';
          _controller.selection = TextSelection.fromPosition(
            TextPosition(offset: _controller.text.length),
          );
        } else if (_voiceBaseText.isNotEmpty) {
          // speech_to_text 7.x fires _onResult(partial, '') as a plugin
          // cleanup step between _onStatus('done') and _onResult(finalResult).
          // Do NOT update the controller or clear _voiceBaseText here —
          // _onResult(final) is still in flight and needs the base intact.
        }
      }

      setState(() {});
    });
  }

  @override
  void dispose() {
    _typeTimer?.cancel();
    _holdTimer?.cancel();
    _countdownTimer?.cancel();
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
    if (_voice.isRecording || _voice.isLongDictating) {
      HapticFeedback.lightImpact();
      _stopCountdownTimer();
      await _voice.stop();
      setState(() {});
      return;
    }
    // Snapshot the current text; listener merges all partials/finals onto this.
    _voiceBaseText = _controller.text;
    final ok = await _voice.start();
    if (ok) {
      HapticFeedback.lightImpact();
      _startCountdownTimer();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Microphone or speech permission denied. '
            'Please enable it in Settings and try again.',
          ),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    setState(() {});
  }

  void _startCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _stopCountdownTimer() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
  }

  // ---------------------------------------------------------------------------
  // SUBMIT TASK → /process_task
  // ---------------------------------------------------------------------------

  Future<void> _sendRequest() async {
    // Dismiss keyboard immediately — safe here because this is before any await.
    FocusScope.of(context).unfocus();

    // If the mic is active, stop it before reading the controller text.
    // _voice.stop() → _endLongDictation() → notifyListeners() → our voice
    // listener commits finalText into _controller synchronously, so the text
    // read below already includes the last spoken words.
    // This also cancels _restartTimer and any pending auto-restart inside
    // SpeechService, so nothing continues running in the background.
    if (_voice.isRecording || _voice.isLongDictating) {
      _stopCountdownTimer();
      await _voice.stop();
      if (!mounted) return;
    }

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
          msg = "We can't assist with adult, intimate, or inappropriate tasks.";
        } else if (type == 'illegal') {
          msg =
              "We can't support anything illegal or risky. Please try another task.";
        } else if (type == 'dangerous') {
          msg = "We can't help with tasks involving danger, weapons, or harm.";
        } else if (type == 'scam') {
          msg =
              "This request appears unsafe or deceptive. Please try another one.";
        } else if (type == 'medical') {
          msg = "We can't provide medical or health-risk related tasks.";
        } else if (type == 'nonsense') {
          msg = "Tell us a clear task you need help with—try again.";
        } else if (type == 'personal_services') {
          msg =
              "We can't assist with intimate or personal companionship tasks.";
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
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final canSend = _controller.text.trim().isNotEmpty && !_isLoading;
    final isTyping = _controller.text.trim().isNotEmpty;
    // True whenever the software keyboard is covering part of the screen.
    // Used to collapse non-essential sections and prevent bottom overflow.
    final keyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    // Responsive vertical spacing — interpolate between iPhone SE (667pt)
    // and iPhone Pro Max (932pt) so content breathes on tall screens without
    // leaving a blank void on compact ones.
    final screenH = MediaQuery.of(context).size.height;
    final t = ((screenH - 667.0) / 265.0).clamp(0.0, 1.0);
    final topPad = 48.0 + t * 12.0; // 48–60 — clears the Positioned overlay row
    final heroGap = 10.0 + t * 6.0; // 10–16 — compact so input stays central
    // Leave room for the active job banner when visible; collapse when keyboard open.
    final bottomPad = keyboardOpen ? 0.0 : (_activeJobId != null ? 96.0 : 16.0);

    // Hero is supportive — input card is the visual center.
    final heroFontSize = (22.0 + t * 6.0).clamp(22.0, 28.0);
    final subtitleFontSize = (12.5 + t * 1.5).clamp(12.5, 14.0);

    return Scaffold(
      backgroundColor: _kGround,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 22.0),
          child: Stack(
            children: [
              // Main column fills SafeArea height.
              // Expanded in the middle section vertically centres the input
              // card between the hero text and the bottom card on any device.
              Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(height: topPad),

                  // ── Compact wordmark with saffron underline ────────────
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Zanzo',
                        style: TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w500,
                          color: _kInk,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Container(
                        width: 28,
                        height: 2.5,
                        decoration: BoxDecoration(
                          color: _kSaffron,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: heroGap),

                  // ── Hero ──────────────────────────────────────────────
                  Text(
                    'Hire a human\nnear you',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: heroFontSize,
                      fontWeight: FontWeight.w500,
                      color: _kInk,
                      height: 1.05,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    "Tell Zanzo what you need — we'll turn it into action.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: subtitleFontSize,
                      color: _kMuted,
                      fontWeight: FontWeight.w400,
                      height: 1.4,
                    ),
                  ),

                  // ── Input card + trust strip — vertically centred ─────
                  // Expanded absorbs the space between the hero text and the
                  // bottom "Happening near you" section so the input sits at
                  // the true visual midpoint on every screen size.
                  // The bottom padding biases the column slightly above centre,
                  // which reads more naturally when the hero text sits close
                  // above and the bottom card is anchored below.
                  Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: keyboardOpen ? 0 : 60),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [

                        // ── Elevated prompt card ──────────────────────────
                        AnimatedBuilder(
                          animation: _glowAnim,
                          builder: (context, _) {
                            return Container(
                              decoration: BoxDecoration(
                                // Subtle warm gradient — top bright white,
                                // base drifts toward the off-white ground colour.
                                // Gives a softly lifted, premium surface feel
                                // without blur or heavy effects.
                                gradient: const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Color(0xFFFFFFFF),  // bright white top
                                    Color(0xFFFEFBF6),  // warm tinted base
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(26),
                                border: Border.all(
                                  color: _kInk.withValues(alpha: 0.08),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(
                                      alpha: 0.08 + (_glowAnim.value * 0.04),
                                    ),
                                    blurRadius: 36 + (10 * _glowAnim.value),
                                    spreadRadius: 0,
                                    offset: Offset(0, 12 + (3 * _glowAnim.value)),
                                  ),
                                  // Warm ambient glow — premium feel without blur
                                  BoxShadow(
                                    color: _kSaffron.withValues(
                                      alpha: 0.04 + (_glowAnim.value * 0.03),
                                    ),
                                    blurRadius: 48,
                                    spreadRadius: 0,
                                    offset: const Offset(0, 10),
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 14,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Expanded(
                                    child: ConstrainedBox(
                                      constraints: const BoxConstraints(
                                        minHeight: 100,
                                        maxHeight: 200,
                                      ),
                                      child: TextField(
                                        controller: _controller,
                                        onChanged: (_) => setState(() {}),
                                        onSubmitted: (_) =>
                                            canSend ? _sendRequest() : null,
                                        minLines: 4,
                                        maxLines: 8,
                                        keyboardType: TextInputType.multiline,
                                        textInputAction: TextInputAction.newline,
                                        style: const TextStyle(
                                          color: _kInk,
                                          fontSize: 15,
                                          height: 1.4,
                                        ),
                                        decoration: const InputDecoration(
                                          hintText: 'Type or speak your request…',
                                          hintStyle: TextStyle(
                                            color: _kMuted,
                                            fontSize: 15,
                                          ),
                                          border: InputBorder.none,
                                          contentPadding: EdgeInsets.zero,
                                        ),
                                      ),
                                    ),
                                  ),

                                  // Mic — voice input, left of send
                                  _MicButton(
                                    isRecording: _voice.isRecording,
                                    isLongDictating: _voice.isLongDictating,
                                    onPressed: _toggleVoice,
                                  ),
                                  const SizedBox(width: 4),

                                  // Send — saffron circle, rightmost final action
                                  GestureDetector(
                                    onTap: canSend ? _sendRequest : null,
                                    child: Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: canSend
                                            ? _kSaffron
                                            : _kSaffron.withValues(alpha: 0.3),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.arrow_upward_rounded,
                                        color: Colors.white,
                                        size: 22,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),

                        const SizedBox(height: 14),

                        // ── Trust strip ───────────────────────────────────
                        // Row > Expanded forces tight width onto the Wrap so it
                        // always knows when to wrap — Column(center) alone gives
                        // Wrap unbounded width which causes the overflow on narrow
                        // Android screens.
                        const Row(
                          children: [
                            Expanded(
                              child: Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 14,
                                runSpacing: 6,
                                children: [
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.verified_outlined, size: 12, color: _kMuted),
                                      SizedBox(width: 3),
                                      Text(
                                        'Verified ZanCrew',
                                        style: TextStyle(fontSize: 11.5, color: _kMuted),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.lock_outline_rounded, size: 12, color: _kMuted),
                                      SizedBox(width: 3),
                                      Text(
                                        'Secure payment',
                                        style: TextStyle(fontSize: 11.5, color: _kMuted),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.my_location_rounded, size: 12, color: _kMuted),
                                      SizedBox(width: 3),
                                      Text(
                                        'Live tracking',
                                        style: TextStyle(fontSize: 11.5, color: _kMuted),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        // ── Policy message ────────────────────────────────
                        if (_policyMessage != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.red.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.red.withValues(alpha: 0.3),
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

                        if (_isLoading)
                          const Padding(
                            padding: EdgeInsets.only(top: 10),
                            child: CircularProgressIndicator(
                              strokeWidth: 2.6,
                              color: _kSaffron,
                            ),
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

                        ], // Expanded > Column children
                      ),   // Column
                    ),     // Padding
                  ),       // Expanded

                  // ── Happening near you — bottom-anchored ──────────────
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: isTyping || keyboardOpen
                        ? const SizedBox.shrink()
                        : _HappeningCard(
                            key: const ValueKey('happening'),
                            example: _examples[_exIndex],
                            typedText: _typed,
                            onTap: _onExampleTap,
                          ),
                  ),

                  SizedBox(height: bottomPad),
                ], // Column children
              ), // Column

              // ── Customer / Work segmented pill (top-left) ─────────────
              Positioned(
                top: 0,
                left: 0,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Container(
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _kInk.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Customer — selected state (no-op; already on home)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: _kInk,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Text(
                            'Customer',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                            ),
                          ),
                        ),
                        // Work — calls existing _onTapEarn()
                        GestureDetector(
                          onTap: _onTapEarn,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_zancrewStatus == 'active')
                                  Container(
                                    width: 6,
                                    height: 6,
                                    margin: const EdgeInsets.only(right: 5),
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF4ADE80),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                Text(
                                  'Work',
                                  style: TextStyle(
                                    color: _zancrewEnabled
                                        ? _kInk
                                        : _kInk.withValues(alpha: 0.45),
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Profile avatar with saffron ring (top-right) ──────────
              Positioned(
                top: 8,
                right: 0,
                child: GestureDetector(
                  onTap: _onAvatarTap,
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _kSaffron,
                        width: 2,
                      ),
                      color: Colors.white,
                    ),
                    child: Center(
                      child: Text(
                        _avatarInitial,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _kInk,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // ── Active job banner (bottom) — logic untouched ───────────
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
      ),
    );
  }
}

// ===========================================================================
// SMALL UI PIECES
// ===========================================================================

class _MicButton extends StatefulWidget {
  final bool isRecording;
  final bool isLongDictating;
  final VoidCallback onPressed;

  const _MicButton({
    required this.isRecording,
    required this.isLongDictating,
    required this.onPressed,
  });

  @override
  State<_MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<_MicButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void didUpdateWidget(_MicButton old) {
    super.didUpdateWidget(old);
    final active = widget.isRecording || widget.isLongDictating;
    if (active && !_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    } else if (!active && _pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.isRecording || widget.isLongDictating;
    return Padding(
      padding: const EdgeInsets.only(right: 4.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, __) => Container(
              width: 44,
              height: 44,
              decoration: active
                  ? BoxDecoration(
                      shape: BoxShape.circle,
                      color: _kSaffron.withValues(
                        alpha: 0.08 + _pulse.value * 0.09,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _kSaffron.withValues(
                            alpha: 0.16 + _pulse.value * 0.16,
                          ),
                          blurRadius: 10 + _pulse.value * 8,
                        ),
                      ],
                    )
                  : null,
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: Icon(
                  active ? Icons.stop_rounded : Icons.mic_none_rounded,
                  color: active ? _kSaffron : _kInk,
                  size: 26,
                ),
                onPressed: widget.onPressed,
              ),
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
// HAPPENING NEAR YOU CARD — social-proof example, pure display widget
// Shows the currently-cycling example with typewriter text. Tap fills input.
// ===========================================================================

class _HappeningCard extends StatelessWidget {
  final _Example example;
  final String typedText;
  final VoidCallback onTap;

  const _HappeningCard({
    super.key,
    required this.example,
    required this.typedText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'HAPPENING NEAR YOU',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: _kMuted,
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 10),
        GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: _kInk.withValues(alpha: 0.08)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Name initial avatar
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: _kInk,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      example.name[0],
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Name + live dot + task text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            example.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: _kInk,
                              fontSize: 13.5,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF4ADE80),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            example.emoji,
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        typedText.isEmpty ? example.text : typedText,
                        style: const TextStyle(
                          fontSize: 13,
                          color: _kMuted,
                          height: 1.35,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 10),
                // Use action
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Text(
                    'Use →',
                    style: TextStyle(
                      fontSize: 12,
                      color: _kSaffron,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
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
