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
import 'package:zanzo_frontend/core/theme/app_theme.dart';
import 'package:zanzo_frontend/core/services/api_service.dart';
import 'package:zanzo_frontend/core/services/auth.dart';
import 'package:zanzo_frontend/core/services/speech_service.dart';
import 'package:zanzo_frontend/core/services/zancrew_api.dart';
// User feature
import 'package:zanzo_frontend/features/user/screens/profile_screen.dart';
import 'package:zanzo_frontend/features/user/screens/review_task_screen.dart';
import 'package:zanzo_frontend/features/user/screens/track_job_screen.dart';
import 'package:zanzo_frontend/features/user/widgets/login_prompt_dialog.dart';
// ZanCrew
import 'package:zanzo_frontend/features/zancrew/gateway/zancrew_gateway.dart';
import 'package:zanzo_frontend/features/zancrew/screens/zancrew_JobDetails.dart';

// Design tokens now live centrally in AppTheme. These aliases keep the many
// call-sites terse while sourcing every value from the single token file, so
// the brand is defined once — see lib/core/theme/app_theme.dart.
const _kGround = AppColors.ground;
const _kInk = AppColors.ink;
const _kSaffron = AppColors.saffron;
const _kMuted = AppColors.muted;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
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

  // Fires once per fresh app process — resets on cold restart automatically
  // because it is a static field in memory (not persisted to disk).
  static bool _didAutoOpenActiveJobThisSession = false;

  // ---------------------------------------------------------------------------
  // CUSTOMER ACTIVE TASK STATE
  // ---------------------------------------------------------------------------

  String? _customerActiveTaskId;
  String? _customerActiveTaskTitle;
  String? _customerActiveTaskStatus;
  String? _customerActiveTaskLocation;

  static bool _didAutoOpenCustomerActiveTaskThisSession = false;

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
      text:
          'Pick up my prepaid parcel from the post office and bring it to my flat.',
    ),
    _Example(
      emoji: '🛋️',
      name: 'Maya',
      text: 'Wait at my flat for a sofa delivery and let the delivery team in.',
    ),
    _Example(
      emoji: '📄',
      name: 'Sophie',
      text:
          'Collect documents from a nearby office and drop them at my address.',
    ),
    _Example(
      emoji: '🔑',
      name: 'Daniel',
      text:
          'Hand spare keys to a new tenant arriving at 2 PM and note the meter reading.',
    ),
    _Example(
      emoji: '🧹',
      name: 'Yosh',
      text:
          'Wait at my property and hand a spare key to my cleaner arriving at 10 AM.',
    ),
    _Example(
      emoji: '🎁',
      name: 'James',
      text:
          'Drop two small bags of donations at the charity shop two streets away.',
    ),
    _Example(
      emoji: '🏠',
      name: 'Hira',
      text:
          'Wait at my flat for a broadband engineer between 2 and 4 PM and let them in.',
    ),
    _Example(
      emoji: '🎒',
      name: 'Leo',
      text:
          'Collect my forgotten backpack from a friend nearby and bring it to me.',
    ),
  ];

  int _exIndex = 0;
  String _typed = '';
  Timer? _typeTimer;
  Timer? _holdTimer;

  // ---------------------------------------------------------------------------
  // INIT
  // ---------------------------------------------------------------------------

  // Throttle for resume-time location syncs (avoid a call on every app switch).
  DateTime? _lastResumeLocSync;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _registerFcmTokenIfLoggedIn();
    _loadUser();
    _loadZancrewFromPrefs();
    _backgroundSyncZanCrew();
    _checkActiveJob();
    _checkCustomerActiveTask();
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
    WidgetsBinding.instance.removeObserver(this);
    _typeTimer?.cancel();
    _holdTimer?.cancel();
    _countdownTimer?.cancel();
    _glowCtrl.dispose();
    _controller.dispose();
    _voice.disposeAll();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      // Catches the user returning from device Settings after granting location
      // permission — sync location so country_code is set before they post.
      _syncLocationOnResume();
      // Refresh the active-task banners so someone who backgrounded/closed the
      // app mid-task sees (and can tap back into) their current job on Home.
      _checkActiveJob();
      _checkCustomerActiveTask();
    }
  }

  // Best-effort, silent location sync on resume. Does NOT prompt for permission
  // (only checks) and never blocks or shows errors. Throttled so rapid app
  // switches don't spam the endpoint.
  Future<void> _syncLocationOnResume() async {
    try {
      final now = DateTime.now();
      if (_lastResumeLocSync != null &&
          now.difference(_lastResumeLocSync!) < const Duration(seconds: 60)) {
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('access_token');
      if (token == null || token.isEmpty) return; // not signed in

      if (!await Geolocator.isLocationServiceEnabled()) return;
      final permission = await Geolocator.checkPermission();
      if (permission != LocationPermission.always &&
          permission != LocationPermission.whileInUse) {
        return; // permission not granted — don't prompt on resume
      }

      _lastResumeLocSync = now;
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 8));

      await ApiService.setUserLocation(lat: pos.latitude, lng: pos.longitude);
    } catch (_) {
      // Silent — resume sync must never surface an error to the user.
    }
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
      final res = await ApiService.getJson('/zancrew/active_task');
      if (!mounted) return;
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data is Map && data['active'] == true) {
          final jobId = (data['task_id'] ?? data['job_id'])?.toString();
          final jobTitle = data['task_title']?.toString();
          final jobStatus = data['status']?.toString();

          setState(() {
            _activeJobId = jobId;
            _activeJobTitle = jobTitle;
            _activeJobStatus = jobStatus;
          });

          // Auto-open CrewJobDetail once per fresh app session so the worker
          // lands directly on their in-progress job without any extra taps.
          // The static guard means pressing back returns to Home normally and
          // the screen will never auto-open again until the app is restarted.
          if (!_didAutoOpenActiveJobThisSession &&
              jobId != null &&
              jobStatus != 'completed' &&
              jobStatus != 'cancelled') {
            _didAutoOpenActiveJobThisSession = true;
            WidgetsBinding.instance.addPostFrameCallback((_) async {
              if (!mounted) return;
              await Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => CrewJobDetail(jobId: jobId)),
              );
              if (mounted) _checkActiveJob();
            });
          }
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
  // CUSTOMER ACTIVE TASK CHECK
  // ---------------------------------------------------------------------------

  Future<void> _checkCustomerActiveTask() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('user_id') ?? '';
    if (userId.isEmpty) return;
    try {
      final data = await ApiService.getCustomerActiveTask();
      if (!mounted) return;
      if (data != null && data['active'] == true) {
        final taskId = data['task_id']?.toString();
        final taskTitle = data['title']?.toString();
        final taskStatus = data['status']?.toString();
        final taskLocation = data['location_address']?.toString();

        setState(() {
          _customerActiveTaskId = taskId;
          _customerActiveTaskTitle = taskTitle;
          _customerActiveTaskStatus = taskStatus;
          _customerActiveTaskLocation = taskLocation;
        });

        const activeStatuses = {
          'assigned',
          'travelling',
          'arrived',
          'in_progress',
        };
        if (!_didAutoOpenCustomerActiveTaskThisSession &&
            taskId != null &&
            activeStatuses.contains(taskStatus)) {
          _didAutoOpenCustomerActiveTaskThisSession = true;
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (!mounted) return;
            // Skip if a TrackJobScreen for this job is already open (e.g. one
            // already pushed via the Live Activity deep link) so we don't stack.
            if (TrackJobScreen.isOpenForJob(taskId)) return;
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => TrackJobScreen(
                  taskTitle: taskTitle ?? 'Task',
                  userLocation: taskLocation ?? '',
                  jobId: taskId,
                ),
              ),
            );
            if (mounted) _checkCustomerActiveTask();
          });
        }
        return;
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _customerActiveTaskId = null;
        _customerActiveTaskTitle = null;
        _customerActiveTaskStatus = null;
        _customerActiveTaskLocation = null;
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
    await _loadUser(); // keep greeting / avatar in sync after first login

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

      // ── Sync the freshly-fetched location to the backend ─────────────────
      // setUserLocation returns a new JWT with country_code embedded, which
      // task creation depends on. At login this sync is best-effort and is
      // skipped if permission was still denied — so a user who granted location
      // afterwards (e.g. from device Settings) would otherwise never have their
      // country set. Re-syncing here guarantees the first post picks up the now-
      // granted location. Await only when country_code isn't set yet (so
      // processTask uses the refreshed token); otherwise keep it non-blocking.
      if (pos != null) {
        final prefs = await SharedPreferences.getInstance();
        final hasCountry = (prefs.getString('country_code') ?? '').isNotEmpty;
        final syncFuture = ApiService.setUserLocation(
          lat: pos.latitude,
          lng: pos.longitude,
        );
        if (hasCountry) {
          unawaited(syncFuture);
        } else {
          await syncFuture;
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
              initialLat: pos?.latitude,
              initialLng: pos?.longitude,
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
    // Only require login when no phone is stored — a signed-in user with no
    // name yet should still reach ProfileScreen, not see the login dialog.
    if (_userPhone == null) {
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
    if (n == null || n.isEmpty) return '?';
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
      await _loadUser(); // sync name/phone into state after login
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
    // While the keyboard is open the fixed top chrome collapses so the input
    // card keeps its full height (otherwise its Expanded is squeezed below its
    // min height and the column overflows — the "bottom overflowed" error).
    final topPad = keyboardOpen
        ? 52.0 // still clears the Positioned pill/avatar overlay row
        : 48.0 + t * 12.0; // 48–60 — clears the Positioned overlay row
    final heroGap = keyboardOpen
        ? 8.0
        : 20.0 + t * 4.0; // 20–24 — breathing room between wordmark and hero

    // Hero is supportive — input card is the visual center.
    final heroFontSize = (18.0 + t * 6.0).clamp(18.0, 24.0);
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
                // Main column fills SafeArea height and SCROLLS when the
                // keyboard shrinks the viewport, so it can never overflow on
                // any device / font scale:
                //  • ConstrainedBox(minHeight) keeps the Expanded-centred
                //    layout when there's room (content == viewport height);
                //  • IntrinsicHeight lets the Expanded work inside the scroll
                //    view (which otherwise gives unbounded height);
                //  • SingleChildScrollView absorbs any height deficit.
                LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: IntrinsicHeight(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            SizedBox(height: topPad),

                            // ── Compact wordmark with saffron underline ────────────
                            // Hidden while typing to free vertical room for the keyboard.
                            if (!keyboardOpen)
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text('Zanzo', style: AppText.wordmark),
                                  const SizedBox(height: 6),
                                  // Small saffron "voice bar" under the wordmark
                                  Container(
                                    width: 22,
                                    height: 3,
                                    decoration: BoxDecoration(
                                      gradient: AppGradients.saffronAction,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                  ),
                                ],
                              ),

                            SizedBox(height: heroGap),

                            // ── Hero ──────────────────────────────────────────────
                            // Hidden while typing to free vertical room for the keyboard.
                            if (!keyboardOpen)
                              Text.rich(
                                TextSpan(
                                  style: TextStyle(
                                    fontSize: heroFontSize,
                                    fontWeight: FontWeight.w600,
                                    height: 1.0,
                                    letterSpacing: -0.5,
                                  ),
                                  children: const [
                                    TextSpan(
                                      text: 'Hire a human\n',
                                      style: TextStyle(color: _kInk),
                                    ),
                                    TextSpan(
                                      text: 'near you',
                                      style: TextStyle(color: _kSaffron),
                                    ),
                                  ],
                                ),
                                textAlign: TextAlign.center,
                              ),
                            // Subtitle hidden while typing to free vertical room.
                            if (!keyboardOpen) ...[
                              const SizedBox(height: 6),
                              Text(
                                (_userName != null &&
                                        _userName!.trim().isNotEmpty)
                                    ? 'Hi ${_userName!.trim().split(' ').first} — tell us what you need.'
                                    : "Tell Zanzo what you need — we'll turn it into action.",
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: subtitleFontSize,
                                  color: _kMuted,
                                  fontWeight: FontWeight.w400,
                                  height: 1.4,
                                ),
                              ),
                            ],

                            // ── Input card + trust strip — vertically centred ─────
                            // Expanded absorbs the space between the hero text and the
                            // bottom "Happening near you" section so the input sits at
                            // the true visual midpoint on every screen size.
                            // The bottom padding biases the column slightly above centre,
                            // which reads more naturally when the hero text sits close
                            // above and the bottom card is anchored below.
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(
                                  bottom: keyboardOpen ? 0 : 60,
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    // ── Elevated prompt card ──────────────────────────
                                    AnimatedBuilder(
                                      animation: _glowAnim,
                                      builder: (context, _) {
                                        return Container(
                                          decoration: BoxDecoration(
                                            // Softly-lifted paper surface that
                                            // "breathes" with the glow anim —
                                            // the tactile hero of the voice-first
                                            // home. All values come from AppTheme.
                                            gradient: AppGradients.liftedCard,
                                            borderRadius: AppRadii.cardR,
                                            border: Border.all(
                                              color: AppColors.hairline(0.08),
                                            ),
                                            boxShadow: AppShadows.lifted(
                                              _glowAnim.value,
                                            ),
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 18,
                                            vertical: 14,
                                          ),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Expanded(
                                                child: ConstrainedBox(
                                                  constraints:
                                                      const BoxConstraints(
                                                        minHeight: 100,
                                                        maxHeight: 200,
                                                      ),
                                                  child: TextField(
                                                    controller: _controller,
                                                    onChanged: (_) =>
                                                        setState(() {}),
                                                    onSubmitted: (_) => canSend
                                                        ? _sendRequest()
                                                        : null,
                                                    minLines: 4,
                                                    maxLines: 8,
                                                    keyboardType:
                                                        TextInputType.multiline,
                                                    textInputAction:
                                                        TextInputAction.newline,
                                                    style: const TextStyle(
                                                      color: _kInk,
                                                      fontSize: 15,
                                                      height: 1.4,
                                                    ),
                                                    decoration:
                                                        const InputDecoration(
                                                          hintText:
                                                              'Type or speak your request…',
                                                          hintStyle: TextStyle(
                                                            color: _kMuted,
                                                            fontSize: 15,
                                                          ),
                                                          border:
                                                              InputBorder.none,
                                                          contentPadding:
                                                              EdgeInsets.zero,
                                                        ),
                                                  ),
                                                ),
                                              ),

                                              // Mic — voice input, left of send
                                              _MicButton(
                                                isRecording: _voice.isRecording,
                                                isLongDictating:
                                                    _voice.isLongDictating,
                                                onPressed: _toggleVoice,
                                              ),
                                              const SizedBox(width: 4),

                                              // Send — living-saffron squircle,
                                              // rightmost final action. Gradient
                                              // + soft glow when armed; matches
                                              // the iOS superellipse feel.
                                              GestureDetector(
                                                onTap: canSend
                                                    ? _sendRequest
                                                    : null,
                                                child: AnimatedContainer(
                                                  duration: const Duration(
                                                    milliseconds: 200,
                                                  ),
                                                  width: 46,
                                                  height: 46,
                                                  decoration: BoxDecoration(
                                                    gradient: canSend
                                                        ? AppGradients
                                                              .saffronAction
                                                        : null,
                                                    color: canSend
                                                        ? null
                                                        : AppColors.saffronTint(
                                                            0.25,
                                                          ),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          16,
                                                        ),
                                                    boxShadow: canSend
                                                        ? [
                                                            BoxShadow(
                                                              color: AppColors
                                                                  .saffron
                                                                  .withValues(
                                                                    alpha: 0.35,
                                                                  ),
                                                              blurRadius: 14,
                                                              offset:
                                                                  const Offset(
                                                                    0,
                                                                    4,
                                                                  ),
                                                            ),
                                                          ]
                                                        : null,
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
                                                  Icon(
                                                    Icons.verified_outlined,
                                                    size: 12,
                                                    color: _kMuted,
                                                  ),
                                                  SizedBox(width: 3),
                                                  Text(
                                                    'Verified ZanCrew',
                                                    style: TextStyle(
                                                      fontSize: 11.5,
                                                      color: _kMuted,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.lock_outline_rounded,
                                                    size: 12,
                                                    color: _kMuted,
                                                  ),
                                                  SizedBox(width: 3),
                                                  Text(
                                                    'Secure payment',
                                                    style: TextStyle(
                                                      fontSize: 11.5,
                                                      color: _kMuted,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.my_location_rounded,
                                                    size: 12,
                                                    color: _kMuted,
                                                  ),
                                                  SizedBox(width: 3),
                                                  Text(
                                                    'Live tracking',
                                                    style: TextStyle(
                                                      fontSize: 11.5,
                                                      color: _kMuted,
                                                    ),
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
                                            color: Colors.red.withValues(
                                              alpha: 0.08,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            border: Border.all(
                                              color: Colors.red.withValues(
                                                alpha: 0.3,
                                              ),
                                            ),
                                          ),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
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
                                          style: const TextStyle(
                                            color: Colors.red,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ),
                                  ], // Expanded > Column children
                                ), // Column
                              ), // Padding
                            ), // Expanded
                            // ── Customer active task card ─────────────────────────
                            if (!isTyping &&
                                !keyboardOpen &&
                                _customerActiveTaskId != null) ...[
                              const SizedBox(height: 10),
                              _CustomerActiveTaskBanner(
                                taskTitle: _customerActiveTaskTitle,
                                rawStatus: _customerActiveTaskStatus,
                                onTap: () async {
                                  // Don't stack a second copy if it's already open.
                                  if (TrackJobScreen.isOpenForJob(
                                    _customerActiveTaskId,
                                  )) {
                                    return;
                                  }
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => TrackJobScreen(
                                        taskTitle:
                                            _customerActiveTaskTitle ?? 'Task',
                                        userLocation:
                                            _customerActiveTaskLocation ?? '',
                                        jobId: _customerActiveTaskId!,
                                      ),
                                    ),
                                  );
                                  if (mounted) _checkCustomerActiveTask();
                                },
                              ),
                            ],
                            // ── Active job card (crew) ─────────────────────────────
                            if (!isTyping &&
                                !keyboardOpen &&
                                _activeJobId != null) ...[
                              const SizedBox(height: 8),
                              _ActiveJobBanner(
                                taskTitle: _activeJobTitle,
                                rawStatus: _activeJobStatus,
                                onTap: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          CrewJobDetail(jobId: _activeJobId!),
                                    ),
                                  );
                                  _checkActiveJob();
                                },
                              ),
                            ],
                            // ── Happening near you — hidden while any active card shows
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              child:
                                  isTyping ||
                                      keyboardOpen ||
                                      _customerActiveTaskId != null ||
                                      _activeJobId != null
                                  ? const SizedBox.shrink()
                                  : _HappeningCard(
                                      key: const ValueKey('happening'),
                                      example: _examples[_exIndex],
                                      typedText: _typed,
                                      onTap: _onExampleTap,
                                    ),
                            ),

                            const SizedBox(height: 16),
                          ], // Column children
                        ), // Column
                      ), // IntrinsicHeight
                    ), // ConstrainedBox
                  ), // SingleChildScrollView
                ), // LayoutBuilder
                // ── Customer / Work segmented pill (top-left) ─────────────
                Positioned(
                  top: 0,
                  left: 0,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: AppRadii.pillR,
                        border: Border.all(color: AppColors.hairline(0.1)),
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
                              color: _kSaffron,
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_zancrewStatus == 'active')
                                    Container(
                                      width: 6,
                                      height: 6,
                                      margin: const EdgeInsets.only(right: 5),
                                      decoration: const BoxDecoration(
                                        color: AppColors.success,
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
                        border: Border.all(color: _kSaffron, width: 2),
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
                    color: AppColors.parcelTint,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      example.name[0],
                      style: const TextStyle(
                        color: AppColors.parcelInk,
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
                              color: AppColors.success,
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
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceWarm,
          borderRadius: AppRadii.bannerR,
          border: Border.all(color: AppColors.hairline(0.1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const _PulsingDot(color: AppColors.success),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'ON DUTY NOW',
                    style: TextStyle(
                      color: _kMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                  if (hasTitle) ...[
                    const SizedBox(height: 2),
                    Text(
                      taskTitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _kInk,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                  if (nextStep != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      nextStep,
                      style: const TextStyle(
                        color: _kMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            if (label.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.successTint(0.18),
                  borderRadius: AppRadii.pillR,
                ),
                child: Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.successInk,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1,
                  ),
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: _kSaffron,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'Return to job',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// CUSTOMER ACTIVE TASK BANNER — warm card shown when customer has active task
// ===========================================================================

class _CustomerActiveTaskBanner extends StatelessWidget {
  final String? taskTitle;
  final String? rawStatus;
  final VoidCallback onTap;

  const _CustomerActiveTaskBanner({
    required this.taskTitle,
    required this.rawStatus,
    required this.onTap,
  });

  String get _statusText {
    switch (rawStatus) {
      case 'assigned':
        return 'ZanCrew accepted your task';
      case 'travelling':
        return 'ZanCrew is travelling';
      case 'arrived':
        return 'ZanCrew has arrived';
      case 'in_progress':
        return 'Task in progress';
      default:
        return 'Active task';
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasTitle = taskTitle != null && taskTitle!.isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: AppColors.surfaceWarmAlt,
          borderRadius: AppRadii.bannerR,
          border: Border.all(
            color: _kSaffron.withValues(alpha: 0.65),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.07),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: _kSaffron.withValues(alpha: 0.10),
              blurRadius: 24,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const _PulsingDot(color: _kSaffron),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'ACTIVE TASK',
                    style: TextStyle(
                      color: _kMuted,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                  if (hasTitle) ...[
                    const SizedBox(height: 2),
                    Text(
                      taskTitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _kInk,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    _statusText,
                    style: const TextStyle(
                      color: _kMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: _kSaffron,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                'Track task',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// PULSING STATUS DOT — slow opacity + glow, no layout shift
// ===========================================================================

class _PulsingDot extends StatefulWidget {
  final Color color;

  const _PulsingDot({required this.color});

  @override
  State<_PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<_PulsingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  late final Animation<double> _anim = CurvedAnimation(
    parent: _ctrl,
    curve: Curves.easeInOut,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: widget.color.withValues(alpha: 0.45 + _anim.value * 0.55),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: widget.color.withValues(alpha: _anim.value * 0.35),
              blurRadius: 4 + _anim.value * 4,
              spreadRadius: _anim.value,
            ),
          ],
        ),
      ),
    );
  }
}
