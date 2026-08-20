// lib/features/user/screens/track_job_screen.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zanzo_frontend/core/theme/app_theme.dart';
import 'package:zanzo_frontend/core/live_activity/job_live_activity.dart';
import 'package:zanzo_frontend/core/services/api_service.dart';
import 'package:zanzo_frontend/core/services/task_events_ws_service.dart';
import 'package:zanzo_frontend/core/services/task_chat_ws_service.dart';
import 'package:zanzo_frontend/core/notifications/chat_unread_store.dart';
import 'package:zanzo_frontend/core/notifications/push_router.dart';
import 'package:zanzo_frontend/core/services/zancrew_api.dart';
import 'package:zanzo_frontend/features/common/chat/chat_screen.dart';
import 'package:zanzo_frontend/features/common/reviews/crew_reviews.dart';

class TrackJobScreen extends StatefulWidget {
  final String taskTitle;
  final String userLocation;
  final String? jobId;
  final Map<String, dynamic>? assignedCrew;

  const TrackJobScreen({
    super.key,
    required this.taskTitle,
    required this.userLocation,
    this.jobId,
    this.assignedCrew,
  });

  // jobIds that currently have a *mounted* TrackJobScreen. Maintained ONLY by
  // initState (add) / dispose (remove) — never reserved ahead of a push — so it
  // can never get "stuck" and block a legitimate open. Auto-open / deep-link /
  // banner push sites consult it to avoid stacking a duplicate for the same job
  // (each duplicate would run its own poll + Live Activity sync and race).
  static final Set<String> _mountedJobIds = <String>{};

  static bool isOpenForJob(String? jobId) =>
      jobId != null && jobId.isNotEmpty && _mountedJobIds.contains(jobId);

  @override
  State<TrackJobScreen> createState() => _TrackJobScreenState();
}

class _TrackJobScreenState extends State<TrackJobScreen> {
  // ---------------- Friendly time progress ----------------
  int _durationMinutes = 0; // from jobs.duration_hours * 60

  // ---------------- Session (Start/End PIN + summary) ----------------
  String? _startPin;
  String? _endPin;
  bool _startPinUsed = false;
  bool _endPinUsed = false;
  DateTime? _startConfirmedAt;
  DateTime? _endConfirmedAt;
  int _minutesWorked = 0;

  Future<void> _loadSession() async {
    if (widget.jobId == null || widget.jobId!.isEmpty) return;

    try {
      final m = await ApiService.getJobSession(widget.jobId!);
      if (!mounted) return;

      setState(() {
        _startPin = (m['start_otp'] ?? '').toString();

        final ep = m['end_otp'];
        _endPin = (ep == null) ? null : ep.toString();

        _startPinUsed = (m['start_otp_verified'] == true);
        _endPinUsed = (m['end_otp_verified'] == true);
      });
      _recomputeCountdown();
    } catch (_) {
      // Session not ready – UI will stay without PINs
    }
  }

  // ---------------- Status → Stage mapping ----------------
  static const List<String> baseStages = <String>[
    "Finding nearest ZenCrew",
    "Agent accepted the job",
    "Agent is travelling",
    "Agent arrived",
    "Work in progress",
    "Task completed",
  ];

  final Map<String, int> statusToIndex = const {
    'created': 0,
    'payment_pending': 0,
    'paid': 0,
    'finding_agent': 0,
    'searching': 0,
    'assigned': 1,
    'travelling': 2,
    'traveling': 2,
    'en_route': 2,
    'arrived': 3,
    'in_progress': 4,
    'started': 4,
    'completed': 5,
    'settled': 5,
  };

  int currentStage = 0;
  String _jobStatus = '';
  bool _loading = false;

  // ---------------- Realtime + polling ----------------
  TaskEventsWsService? _wsTask;
  Timer? _simTimer;
  Timer? _pollTimer;
  Timer? _sessionTimer;

  // Latest crew location from WS (scaffolded for future map view).
  // ignore: unused_field
  double? _crewLat;
  // ignore: unused_field
  double? _crewLng;

  // Subtle pulse for current stage (tiny, premium)
  Timer? _pulseTimer;
  bool _pulse = false;

  Map<String, dynamic>? _assignedCrew;

  // ---------------- Live chat unread badge ----------------
  TaskChatWsService? _chatWs;
  String? _viewerUserId;
  final Set<String> _seenChatIds = <String>{};
  bool _chatSeeded = false;
  int _unreadChat = 0;

  // ---------------- Crew rating / review ----------------
  double? _crewAvg;
  int _crewCount = 0;
  String? _crewRatingLoadedFor; // user_id we've fetched the summary for
  bool _reviewPrompted = false; // guard so the review sheet shows once

  // ---------------- Theme tokens ----------------
  // Sourced from the central AppTheme so this screen shares Home's exact
  // saffron/ink — previously it drifted to an amber #D97706 accent and a
  // colder #26211C ink. See lib/core/theme/app_theme.dart.
  static const Color _accent = AppColors.saffron;
  static const Color _bg = AppColors.ground;
  static const Color _surface = AppColors.surfaceMuted;
  static const Color _card = AppColors.surface;
  static const Color _ink = AppColors.ink;
  static const Color _muted = AppColors.muted;
  static const Color _line = AppColors.divider;
  static const Color _success = AppColors.successInk;
  static const Color _warning = AppColors.warning;

  @override
  void initState() {
    super.initState();
    _assignedCrew = widget.assignedCrew;
    if (widget.jobId != null && widget.jobId!.isNotEmpty) {
      TrackJobScreen._mountedJobIds.add(widget.jobId!);
    }
    if (_assignedCrew != null) _loadCrewRating();

    _pulseTimer = Timer.periodic(const Duration(milliseconds: 900), (_) {
      if (!mounted) return;
      setState(() => _pulse = !_pulse);
    });

    if (widget.jobId != null && widget.jobId!.isNotEmpty) {
      _fetchCurrentStatus();
      _startPolling();
      _startWs(widget.jobId!);
      _loadSession();
      _startChatUnreadWatch(widget.jobId!);
    } else {
      _startProgressSimulation();
    }
  }

  // ---------------- Live chat unread ----------------
  Future<void> _startChatUnreadWatch(String jobId) async {
    _viewerUserId = await _resolveViewerUserId();
    if (!mounted) return;
    // The unread badge is sourced from the shared store (also fed by FCM
    // pushes while this screen is away), so seed from it and listen for changes.
    ChatUnreadStore.instance.addListener(_onUnreadStoreChanged);
    unawaited(ChatUnreadStore.instance.load());
    _syncUnreadFromStore();
    final ws = TaskChatWsService(jobId)..addListener(_onChatWsUpdate);
    _chatWs = ws;
    // Seed with existing history so old messages don't count as "unread".
    unawaited(ws.connect());
  }

  void _onUnreadStoreChanged() => _syncUnreadFromStore();

  void _syncUnreadFromStore() {
    final jobId = widget.jobId;
    if (jobId == null || !mounted) return;
    final count = ChatUnreadStore.instance.countFor(jobId);
    if (count != _unreadChat) {
      setState(() => _unreadChat = count);
      _syncLiveActivity(); // reflect the unread badge in the Dynamic Island
    }
  }

  void _onChatWsUpdate() {
    final ws = _chatWs;
    final jobId = widget.jobId;
    if (ws == null || jobId == null || !mounted) return;
    // On the first sync (the connected/history frame), treat everything already
    // in the room as seen so old messages don't show up as unread.
    if (!_chatSeeded) {
      _chatSeeded = true;
      for (final m in ws.messages) {
        _seenChatIds.add(m.id);
      }
      return;
    }
    // A push may have counted the same message already — the store dedupes by id.
    final viewingThisChat = PushRouter.currentChatTaskId == jobId;
    for (final m in ws.messages) {
      final fromOther =
          _viewerUserId == null || m.senderUserId != _viewerUserId;
      if (fromOther && !_seenChatIds.contains(m.id)) {
        _seenChatIds.add(m.id);
        if (!viewingThisChat) {
          unawaited(ChatUnreadStore.instance.add(jobId, m.id));
        }
      }
    }
  }

  void _markChatSeen() {
    final ws = _chatWs;
    if (ws != null) {
      for (final m in ws.messages) {
        _seenChatIds.add(m.id);
      }
    }
    final jobId = widget.jobId;
    if (jobId != null) unawaited(ChatUnreadStore.instance.clear(jobId));
  }

  // ---------------- Data sources ----------------
  Future<void> _fetchCurrentStatus() async {
    if (widget.jobId == null || widget.jobId!.isEmpty) return;

    setState(() => _loading = true);
    try {
      final res = await ApiService.getJob(widget.jobId!);
      if (res.statusCode == 200) {
        final m = json.decode(res.body) as Map<String, dynamic>;
        final st = (m['status'] as String?) ?? '';
        _updateStageFromStatus(st);

        if (_durationMinutes == 0) {
          final d = m['duration_hours'];
          if (d is num && mounted) {
            setState(() => _durationMinutes = (d * 60).round());
            _recomputeCountdown();
          }
        }

        final norm = _normalize(st);
        if (_isAtOrAfterAssigned(norm)) {
          await _ensureAssigneeFetched();
        }
      }
    } catch (_) {
      // ignored
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startWs(String jobId) {
    _wsTask = TaskEventsWsService(jobId)
      ..onStatusChanged = (status, note) {
        _updateStageFromStatus(status);
        if (_isAtOrAfterAssigned(_normalize(status))) {
          _ensureAssigneeFetched();
        }
      }
      ..onCrewLocation = (lat, lng) {
        if (!mounted) return;
        setState(() {
          _crewLat = lat;
          _crewLng = lng;
        });
      };
    _wsTask!.connect();
  }

  void _startPolling() {
    _pollTimer?.cancel();

    // (Optional performance note): 1500ms is aggressive. Premium apps usually poll 3–5s.
    // Keeping your frequency for now; you can bump later safely.
    _pollTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) async {
      if (!mounted || widget.jobId == null || widget.jobId!.isEmpty) return;

      try {
        final res = await ApiService.getJob(widget.jobId!);
        if (res.statusCode == 200) {
          final data = json.decode(res.body) as Map<String, dynamic>;
          final status = (data['status'] as String?) ?? '';
          _updateStageFromStatus(status);

          if (_isAtOrAfterAssigned(_normalize(status))) {
            await _ensureAssigneeFetched();
          }

          if (_normalize(status) == 'completed') {
            _pollTimer?.cancel();
            _pollTimer = null;
          }
        }
      } catch (_) {}
    });
  }

  bool _isAtOrAfterAssigned(String normStatus) {
    final idx = statusToIndex[normStatus] ?? 0;
    return idx >= 1;
  }

  Future<void> _ensureAssigneeFetched() async {
    final name = (_assignedCrew?['name'] ?? '').toString().trim();
    if (name.isNotEmpty) return;
    await _fetchAssigneeByJobId();
  }

  Future<void> _fetchAssigneeByJobId() async {
    if (widget.jobId == null || widget.jobId!.isEmpty) return;

    try {
      final url = Uri.parse(
        "${ApiService.baseUrl}/zancrew/tasks/${widget.jobId}/assignee",
      );
      final res = await http.get(url, headers: await ApiService.authHeaders());

      if (res.statusCode == 200) {
        final a = json.decode(res.body) as Map<String, dynamic>;
        if (!mounted) return;

        setState(() {
          _assignedCrew = {
            "user_id": a["assigned_crew_user_id"],
            "name": _titleCase((a["assigned_name"] ?? '').toString()),
            "avatar_url": a["avatar_url"],
          };
        });
        _loadCrewRating();
      }
    } catch (e) {
      debugPrint('[track] assignee fetch error: $e');
    }
  }

  /// Fetches the assigned crew's aggregate rating (avg + count) for the card.
  Future<void> _loadCrewRating() async {
    final id = (_assignedCrew?['user_id'] ?? '').toString().trim();
    if (id.isEmpty || _crewRatingLoadedFor == id) return;
    _crewRatingLoadedFor = id;
    try {
      final s = await ZanCrewApi.getUserRatingSummary(id);
      if (!mounted) return;
      setState(() {
        final avg = s['avg_rating'];
        _crewAvg = (avg is num) ? avg.toDouble() : double.tryParse('$avg');
        final c = s['reviews_count'];
        _crewCount = (c is num) ? c.round() : (int.tryParse('$c') ?? 0);
      });
    } catch (e) {
      debugPrint('[track] crew rating fetch error: $e');
    }
  }

  Future<String?> _resolveViewerUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id');
  }

  Future<void> _openChat() async {
    final viewerUserId = await _resolveViewerUserId();
    if (!mounted) return;

    _markChatSeen(); // entering the chat clears the unread badge
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          jobId: widget.jobId ?? '',
          jobTitle: widget.taskTitle,
          viewerUserId: viewerUserId,
        ),
      ),
    );
    _markChatSeen(); // messages read while inside the chat are now seen
  }

  /// Chat entry point to the assigned crew, with a live unread-count badge.
  Widget _chatWithCrewButton({double iconSize = 24}) {
    return IconButton(
      tooltip: 'Chat with Crew',
      onPressed: _openChat,
      color: _ink,
      icon: Badge(
        isLabelVisible: _unreadChat > 0,
        label: Text(_unreadChat > 99 ? '99+' : '$_unreadChat'),
        backgroundColor: _accent,
        textColor: Colors.white,
        child: Icon(Icons.chat_bubble_outline_rounded, size: iconSize),
      ),
    );
  }

  void _openSupportSheet() {
    if (widget.jobId == null || widget.jobId!.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SupportSheet(taskId: widget.jobId!),
    );
  }

  // ---------------- Helpers ----------------
  String _normalize(dynamic statusVal) {
    if (statusVal == null) return '';
    var s = statusVal.toString().toLowerCase().trim();
    if (s == 'started') s = 'in_progress';
    if (s == 'traveling' || s == 'en_route') s = 'travelling';
    return s;
  }

  String _titleCase(String input) {
    if (input.trim().isEmpty) return input;
    return input
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) => w[0].toUpperCase() + (w.length > 1 ? w.substring(1) : ''))
        .join(' ');
  }

  void _updateStageFromStatus(dynamic statusVal) {
    final status = _normalize(statusVal);
    final idx = statusToIndex[status];

    if (!mounted) return;
    final wasSearching = _jobStatus == 'searching';
    final prevStatus = _jobStatus;
    setState(() {
      if (idx != null && idx != currentStage) currentStage = idx;
      _jobStatus = status;
    });
    if (!wasSearching && status == 'searching') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Your job is live! We're finding a ZanCrew member near you.",
          ),
          duration: Duration(seconds: 4),
        ),
      );
    }
    // Refresh session flags when status transitions to in_progress or completed/settled,
    // so Start/End PIN verified state reflects the backend immediately without needing
    // the user to tap "Update". Only fires on a status change, not every poll tick.
    if (prevStatus != status &&
        (status == 'in_progress' ||
            status == 'completed' ||
            status == 'settled')) {
      _loadSession();
    }

    // A task going in_progress means the crew just verified the Start-OTP, so
    // start the working countdown immediately (locally) instead of waiting for
    // the _loadSession network round-trip — otherwise the DI reflects the new
    // stage instantly but the countdown only appears a couple of seconds later.
    if (prevStatus != status &&
        (status == 'in_progress' || status == 'started')) {
      if (!_startPinUsed) _startPinUsed = true;
      _recomputeCountdown();
    }

    // Once the task completes, invite the customer to review their crew (once).
    if (prevStatus != status &&
        (status == 'completed' || status == 'settled')) {
      _maybePromptReview();
    }

    _syncLiveActivity(status);
  }

  /// Shows the crew-review sheet a single time after completion, unless this
  /// job was already reviewed on this device.
  Future<void> _maybePromptReview() async {
    if (_reviewPrompted) return;
    final jobId = widget.jobId;
    if (jobId == null || jobId.isEmpty) return;
    _reviewPrompted = true;

    final prefs = await SharedPreferences.getInstance();
    final key = 'reviewed_$jobId';
    if (prefs.getBool(key) == true) return;

    // Give the completion UI a beat to settle before presenting the sheet.
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted) return;

    final submitted = await showCrewReviewSheet(
      context,
      taskId: jobId,
      crewName: (_assignedCrew?['name'] ?? '').toString(),
    );
    if (submitted) {
      await prefs.setBool(key, true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Thanks for reviewing your crew!')),
        );
      }
      // Refresh the card's rating to reflect the new review.
      _crewRatingLoadedFor = null;
      _loadCrewRating();
    }
  }

  // ---------------- Live Activity (Dynamic Island / Lock Screen) ----------------
  bool _liveActivityStarted = false;
  bool _liveActivityEnded = false;
  // Last state pushed to ActivityKit. iOS throttles Live Activity updates, so we
  // only push when something actually changed (the poll ticks every ~1.5s).
  String? _lastLaSignature;

  /// Mirrors the current tracking state into an iOS Live Activity so the user
  /// can follow their errand from the Lock Screen and Dynamic Island. No-op on
  /// non-iOS / simulated (jobId-less) sessions. See
  /// lib/core/live_activity/job_live_activity.dart.
  void _syncLiveActivity([String? statusArg]) {
    if (widget.jobId == null || widget.jobId!.isEmpty) return;
    if (_liveActivityEnded) return;
    final status = statusArg ?? _jobStatus;

    final stageLabel = (currentStage >= 0 && currentStage < baseStages.length)
        ? baseStages[currentStage]
        : '';
    final crewName = (_assignedCrew?['name'] ?? '').toString().trim();
    final crew = crewName.isEmpty ? null : crewName;

    if (status == 'completed' || status == 'settled') {
      _liveActivityEnded = true;
      _countdownTimer?.cancel();
      JobLiveActivity.instance.end(
        stageIndex: currentStage,
        stageLabel: stageLabel,
        statusRaw: status,
        crewName: crew,
      );
      return;
    }

    // Don't start the activity from a chat/countdown tick before we know a real
    // status — only status updates may kick it off.
    if (!_liveActivityStarted && status.isEmpty) return;

    final end = _countdownEndEpoch;
    final overtime = _isOvertime;
    // Overtime is part of the signature so crossing the deadline pushes exactly
    // one update that flips the Dynamic Island to the red count-up clock.
    final signature =
        '$currentStage|$status|${crew ?? ''}|$_unreadChat|${end ?? 0}|$overtime';

    if (!_liveActivityStarted) {
      _liveActivityStarted = true;
      _lastLaSignature = signature;
      _lastLaPushAt = DateTime.now();
      JobLiveActivity.instance.start(
        taskTitle: widget.taskTitle,
        totalStages: baseStages.length,
        stageIndex: currentStage,
        stageLabel: stageLabel,
        statusRaw: status,
        jobId: widget.jobId ?? '',
        crewName: crew,
        unreadCount: _unreadChat,
        endEpoch: end,
        overtime: overtime,
      );
      return;
    }

    // Push immediately when something changed. Additionally re-push the current
    // state on a slow heartbeat: iOS silently throttles/drops Live Activity
    // updates, and since we cache the last signature a dropped stage/countdown
    // update would otherwise never be re-sent — leaving the DI stuck on a stale
    // stage or countdown end. The heartbeat self-heals that within ~12s without
    // the per-tick spamming that burns the OS update budget.
    final now = DateTime.now();
    final changed = signature != _lastLaSignature;
    final stale = _lastLaPushAt == null ||
        now.difference(_lastLaPushAt!) > const Duration(seconds: 12);
    if (changed || stale) {
      _lastLaSignature = signature;
      _lastLaPushAt = now;
      JobLiveActivity.instance.update(
        stageIndex: currentStage,
        stageLabel: stageLabel,
        statusRaw: status,
        crewName: crew,
        unreadCount: _unreadChat,
        endEpoch: end,
        overtime: overtime,
      );
    }
  }

  DateTime? _lastLaPushAt;

  // ---------------- Task countdown (starts once start-OTP is verified) ----------------
  double? _countdownEndEpoch; // Unix epoch seconds of the task's end
  Timer? _countdownTimer;

  /// Anchors and (re)computes the working countdown. There is no backend start
  /// timestamp, so the moment start-OTP is first seen verified is persisted per
  /// job (survives navigation / restart) and the end = start + duration.
  Future<void> _recomputeCountdown() async {
    final jobId = widget.jobId;
    if (jobId == null || jobId.isEmpty) return;

    final active = _startPinUsed && !_endPinUsed && _durationMinutes > 0;
    if (!active) {
      if (_countdownEndEpoch != null) {
        _countdownEndEpoch = null;
        _countdownTimer?.cancel();
        if (mounted) setState(() {});
        _syncLiveActivity();
      }
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final key = 'countdown_start_$jobId';
    var startEpoch = prefs.getInt(key);
    if (startEpoch == null) {
      startEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await prefs.setInt(key, startEpoch);
    }
    final endEpoch = (startEpoch + _durationMinutes * 60).toDouble();
    if (endEpoch == _countdownEndEpoch) return;
    _countdownEndEpoch = endEpoch;
    if (mounted) setState(() {});
    _syncLiveActivity();

    _countdownTimer?.cancel();
    _wasOvertime = _isOvertime;
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      // When the deadline is crossed, push one Live Activity update so the
      // Dynamic Island flips to the red overtime count-up.
      final nowOvertime = _isOvertime;
      if (nowOvertime != _wasOvertime) {
        _wasOvertime = nowOvertime;
        _syncLiveActivity();
      }
      setState(() {}); // refresh the on-screen countdown text
    });
  }

  bool _wasOvertime = false;

  static String _fmtHms(int totalSeconds) {
    final t = totalSeconds < 0 ? 0 : totalSeconds;
    final h = t ~/ 3600;
    final m = (t % 3600) ~/ 60;
    final s = t % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  /// True once the scheduled countdown has hit zero (we then count up in red).
  bool get _isOvertime {
    final end = _countdownEndEpoch;
    if (end == null) return false;
    return DateTime.now().millisecondsSinceEpoch / 1000 - end >= 0;
  }

  /// Human "12:34" / "1:02:03" remaining before the deadline.
  String get _countdownText {
    final end = _countdownEndEpoch;
    if (end == null) return '';
    final remaining = end - DateTime.now().millisecondsSinceEpoch / 1000;
    if (remaining <= 0) return '00:00';
    return _fmtHms(remaining.floor());
  }

  /// Time elapsed since the deadline, counting up — the overtime clock.
  String get _overtimeText {
    final end = _countdownEndEpoch;
    if (end == null) return '';
    final over = DateTime.now().millisecondsSinceEpoch / 1000 - end;
    return _fmtHms(over.floor());
  }

  Future<void> _cancelJob() async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _line,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Cancel job?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Your payment authorisation will be released and you will not be charged.',
                style: TextStyle(fontSize: 15, color: _ink, height: 1.5),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: _muted,
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'You can only cancel before a ZanCrew partner accepts the job.',
                      style: TextStyle(
                        fontSize: 13,
                        color: _muted,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _ink,
                  side: const BorderSide(color: _line),
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Keep job',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 10),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Cancel job',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true) return;

    try {
      final res = await http.post(
        Uri.parse('${ApiService.baseUrl}/payments/cancel'),
        headers: await ApiService.authHeaders(),
        body: jsonEncode({'task_id': widget.jobId}),
      );
      if (!mounted) return;
      if (res.statusCode >= 200 && res.statusCode < 300) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Job cancelled. Your payment authorisation has been released.',
            ),
          ),
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Cancel failed: ${res.body}')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Cancel failed: $e')));
    }
  }

  void _startProgressSimulation() {
    _simTimer?.cancel();
    _simTimer = Timer.periodic(const Duration(seconds: 7), (timer) {
      if (!mounted) return;
      if (currentStage < baseStages.length - 1) {
        setState(() => currentStage += 1);
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    if (widget.jobId != null && widget.jobId!.isNotEmpty) {
      TrackJobScreen._mountedJobIds.remove(widget.jobId!);
    }
    _simTimer?.cancel();
    _pollTimer?.cancel();
    _pulseTimer?.cancel();
    _sessionTimer?.cancel();
    _wsTask?.dispose();
    ChatUnreadStore.instance.removeListener(_onUnreadStoreChanged);
    _chatWs?.removeListener(_onChatWsUpdate);
    _chatWs?.dispose();
    _countdownTimer?.cancel();
    super.dispose();
  }

  /// Live task countdown, shown once the start-OTP is verified.
  static const Color _overtimeRed = Color(0xFFDC2626);

  Widget _countdownCard() {
    final overtime = _isOvertime;
    final accent = overtime ? _overtimeRed : _accent;
    final valueColor = overtime ? _overtimeRed : _ink;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(
            overtime ? Icons.timelapse_rounded : Icons.timer_outlined,
            color: accent,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  overtime ? 'Overtime (past scheduled end)' : 'Time remaining',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: overtime ? _overtimeRed : _muted,
                    fontWeight: overtime ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  overtime ? '+$_overtimeText' : _countdownText,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: valueColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    final isTaskComplete = currentStage == baseStages.length - 1;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text(
          "Live tracking",
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: _bg,
        foregroundColor: _ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          if (widget.jobId != null &&
              widget.jobId!.isNotEmpty &&
              currentStage >= 1) ...[
            // Once a crew has accepted, the primary header action is talking to
            // them (with a live unread badge); general help moves to secondary.
            _chatWithCrewButton(),
            IconButton(
              tooltip: "Get help",
              icon: const Icon(Icons.help_outline_rounded),
              onPressed: _openSupportSheet,
            ),
          ],
          IconButton(
            tooltip: "Refresh",
            icon: _loading
                ? SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _accent,
                    ),
                  )
                : const Icon(Icons.refresh_rounded),
            onPressed: _loading ? null : _fetchCurrentStatus,
          ),
        ],
      ),
      bottomNavigationBar: _jobStatus == 'searching'
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
                child: SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFDC2626),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: _cancelJob,
                    child: const Text(
                      'Cancel job',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            )
          : null,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
                child: _headerBlock(),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
                child: _statusBanner(isTaskComplete: isTaskComplete),
              ),
            ),

            if (_countdownEndEpoch != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                  child: _countdownCard(),
                ),
              ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                child: _agentCard(),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                child: _pinsCard(),
              ),
            ),

            // Optional time progress (keep, but only when it actually has value)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                child: _timeCardOrNull(),
              ),
            ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 10),
                child: Text(
                  "Progress",
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
              ),
            ),

            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                18,
                0,
                18,
                MediaQuery.of(context).padding.bottom + 18,
              ),
              sliver: SliverToBoxAdapter(child: _timelineCard()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.taskTitle.trim().isEmpty
              ? "Your job"
              : widget.taskTitle.trim(),
          style: TextStyle(
            fontSize: 20.5,
            fontWeight: FontWeight.w800,
            color: _ink,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.location_on_outlined, size: 18, color: _muted),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                widget.userLocation.trim().isEmpty
                    ? "Location not set"
                    : widget.userLocation.trim(),
                style: const TextStyle(
                  fontSize: 14.5,
                  color: _muted,
                  height: 1.25,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Premium reassurance banner: tells user what's happening NOW
  Widget _statusBanner({required bool isTaskComplete}) {
    final String label = _currentStatusLabel();
    final Color tint = isTaskComplete ? AppColors.successBg : _surface;
    // Pulse the dot for active (non-complete) states only
    final double dotSize = (!isTaskComplete && _pulse) ? 11.0 : 9.0;
    final double glowRadius = (!isTaskComplete && _pulse) ? 8.0 : 0.0;

    return Container(
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isTaskComplete ? _success.withValues(alpha: 0.25) : _line,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          // Completed: static green check. Active: pulsing saffron dot.
          if (isTaskComplete)
            Icon(Icons.check_circle_rounded, size: 20, color: _success)
          else
            Container(
              width: dotSize,
              height: dotSize,
              decoration: BoxDecoration(
                color: _accent,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _accent.withValues(alpha: glowRadius > 0 ? 0.35 : 0),
                    blurRadius: glowRadius,
                    spreadRadius: 1,
                  ),
                ],
              ),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: isTaskComplete ? _success : _ink,
              ),
            ),
          ),
          TextButton(
            onPressed: () async {
              await _loadSession();
              if (mounted)
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Updated')));
            },
            style: TextButton.styleFrom(
              foregroundColor: isTaskComplete ? _success : _accent,
            ),
            child: const Text("Update"),
          ),
        ],
      ),
    );
  }

  String _currentStatusLabel() {
    switch (currentStage) {
      case 0:
        return "Looking for a nearby ZanCrew partner";
      case 1:
        return "A ZanCrew partner accepted your job";
      case 2:
        return "Your partner is on the way";
      case 3:
        return "Your partner has arrived";
      case 4:
        return "Work is in progress";
      case 5:
        return "Job completed";
      default:
        return "Tracking your job";
    }
  }

  // ---------------- Agent card ----------------
  void _openCrewProfile() {
    final crew = _assignedCrew;
    if (crew == null) return;
    showCrewProfileSheet(
      context,
      crewUserId: (crew['user_id'] ?? '').toString(),
      crewName: (crew['name'] ?? '').toString(),
      avatarUrl: (crew['avatar_url'] ?? '').toString(),
    );
  }

  Widget _agentCard() {
    final crew = _assignedCrew;
    final name = _titleCase((crew?['name'] ?? '').toString());
    final hasName = name.trim().isNotEmpty;

    return GestureDetector(
      onTap: hasName ? _openCrewProfile : null,
      behavior: HitTestBehavior.opaque,
      child: _softCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: _accent.withValues(alpha: 0.12),
                  child: Text(
                    hasName ? name.characters.first.toUpperCase() : 'Z',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _accent,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasName ? name : "ZanCrew partner",
                        style: TextStyle(
                          fontSize: 16.8,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasName
                            ? "View profile & reviews ›"
                            : "Assigning a partner soon",
                        style: TextStyle(
                          fontSize: 13.5,
                          color: hasName ? _accent : _muted,
                          fontWeight:
                              hasName ? FontWeight.w600 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                _chatWithCrewButton(),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _pill(
                  icon: Icons.star_rounded,
                  label: _crewCount == 0
                      ? "New"
                      : "${_crewAvg?.toStringAsFixed(1) ?? '—'} ($_crewCount)",
                  tint: AppColors.warningBg,
                  fg: _warning,
                ),
                _pill(
                  icon: Icons.verified_rounded,
                  label: "Bank",
                  tint: _surface,
                  fg: _muted,
                ),
                _pill(
                  icon: Icons.verified_rounded,
                  label: "KYC",
                  tint: _surface,
                  fg: _muted,
                ),
              ],
            ),
          ],
        ),
      ),
      ),
    );
  }

  // ---------------- PINs card ----------------
  Widget _pinsCard() {
    final hasStart = (_startPin != null && _startPin!.isNotEmpty);
    final endShown = (_endPin != null && _endPin!.isNotEmpty);
    // Badge driven by session-verified flags (loaded from backend via _loadSession).
    // _startConfirmedAt/_endConfirmedAt are never populated by the current session
    // endpoint, so use the verified boolean flags instead.
    final isActive = (_startPinUsed && !_endPinUsed);
    final isCompleted = _endPinUsed;

    String minsLabel() {
      if (_minutesWorked > 0) return '$_minutesWorked min';
      if (_startPinUsed && !_endPinUsed) return 'Live';
      return '--';
    }

    final badgeText = isCompleted
        ? "Completed"
        : (isActive ? "In progress" : "Not started");
    final badgeColor = isCompleted ? _success : (isActive ? _warning : _muted);
    final badgeBg = isCompleted
        ? AppColors.successBg
        : (isActive ? AppColors.warningBg : _surface);

    return _softCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lock_outline_rounded, color: _accent, size: 20),
                const SizedBox(width: 8),
                Text(
                  "Job PINs",
                  style: TextStyle(
                    fontSize: 16.2,
                    fontWeight: FontWeight.w900,
                    color: _ink,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: badgeBg,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: badgeColor.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Text(
                    badgeText,
                    style: TextStyle(
                      fontSize: 12.2,
                      fontWeight: FontWeight.w800,
                      color: badgeColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),

            _pinRow(
              label: "Start PIN",
              value: hasStart ? _startPin! : "—",
              verified: _startPinUsed,
              help: "Share when your partner arrives",
              emphasize: hasStart,
            ),
            const SizedBox(height: 10),
            _pinRow(
              label: "End PIN",
              value: endShown ? _endPin! : "—",
              verified: _endPinUsed,
              help: endShown
                  ? "Share when the task is finished"
                  : "Visible once work begins",
              emphasize: endShown,
            ),

            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.timer_outlined, size: 18, color: _muted),
                const SizedBox(width: 6),
                Text(
                  "Time: ${minsLabel()}",
                  style: TextStyle(
                    fontSize: 13.8,
                    fontWeight: FontWeight.w700,
                    color: _ink,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),
            Divider(color: _line, height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  isCompleted
                      ? Icons.check_circle_outline_rounded
                      : Icons.lock_rounded,
                  size: 13,
                  color: isCompleted ? _success : _muted,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    isCompleted
                        ? "Job complete. Payment will be released to your partner."
                        : "Payment held securely until your job is complete.",
                    style: TextStyle(
                      fontSize: 12,
                      color: isCompleted ? _success : _muted,
                      fontWeight: FontWeight.w500,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _pinRow({
    required String label,
    required String value,
    required bool verified,
    required String help,
    required bool emphasize,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 3),
              Text(help, style: TextStyle(fontSize: 12.5, color: _muted)),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: emphasize ? _surface : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                border: emphasize ? Border.all(color: _line) : null,
              ),
              child: Text(
                value,
                style: TextStyle(
                  fontSize: emphasize ? 18 : 15,
                  fontWeight: emphasize ? FontWeight.w900 : FontWeight.w600,
                  color: emphasize ? _ink : _muted,
                  letterSpacing: emphasize ? 2.5 : 0.2,
                  fontFeatures: emphasize
                      ? const [FontFeature.tabularFigures()]
                      : const [],
                ),
              ),
            ),
            if (verified) ...[
              const SizedBox(width: 8),
              const Icon(Icons.check_circle_rounded, size: 18, color: _success),
            ],
          ],
        ),
      ],
    );
  }

  // ---------------- Time card ----------------
  Widget _timeCardOrNull() {
    if (!(_durationMinutes > 0 &&
        (_minutesWorked > 0 || _startConfirmedAt != null))) {
      return const SizedBox.shrink();
    }

    final double v = (_minutesWorked / _durationMinutes).clamp(0.0, 1.0);
    return _softCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.timeline_rounded, size: 18, color: _muted),
                const SizedBox(width: 8),
                Text(
                  (_endConfirmedAt == null) ? "Time progress" : "Time summary",
                  style: TextStyle(fontWeight: FontWeight.w900, color: _ink),
                ),
                const Spacer(),
                Text(
                  '$_minutesWorked m / ${_durationMinutes}m',
                  style: const TextStyle(
                    color: _muted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: v,
                minHeight: 9,
                backgroundColor: _line,
                valueColor: AlwaysStoppedAnimation<Color>(_accent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------- Timeline (LIVE • breathing) ----------------
  Widget _timelineCard() {
    final displayName = _titleCase((_assignedCrew?['name'] ?? '').toString());

    final stages = <String>[
      "Searching nearby ZanCrew",
      displayName.isNotEmpty
          ? "$displayName accepted the job"
          : "ZanCrew accepted the job",
      displayName.isNotEmpty
          ? "$displayName is travelling"
          : "ZanCrew is travelling",
      displayName.isNotEmpty ? "$displayName arrived" : "ZanCrew arrived",
      "Work in progress",
      "Job completed",
    ];

    // When all stages are done, count the final step as reached too so
    // it shows a check rather than a pulsing dot.
    final isComplete = currentStage == baseStages.length - 1;

    final rawId = widget.jobId ?? '';
    final ticketId = rawId.length >= 5
        ? rawId.substring(rawId.length - 5).toUpperCase()
        : rawId.toUpperCase();

    return _ticketCard(
      ticketId: ticketId,
      child: Column(
        children: List.generate(stages.length, (i) {
            final reached =
                i < currentStage || (isComplete && i == currentStage);
            final isCurrent = !isComplete && i == currentStage;

            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // LEFT: node + breathing connector
                SizedBox(
                  width: 26,
                  child: Column(
                    children: [
                      _timelineNode(reached: reached, isCurrent: isCurrent),
                      if (i < stages.length - 1)
                        _timelineLine(reached: reached, isCurrent: isCurrent),
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                // RIGHT: text
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      stages[i],
                      style: TextStyle(
                        fontSize: 15.5,
                        height: 1.25,
                        fontWeight: isCurrent
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: reached
                            ? _ink
                            : isCurrent
                            ? _ink
                            : _muted,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }),
        ),
      );
  }

  Widget _timelineNode({required bool reached, required bool isCurrent}) {
    final Color ring = reached ? _accent : _line;
    final Color fill = reached ? _accent : Colors.white;

    final double glow = isCurrent ? (_pulse ? 0.30 : 0.12) : 0.0;

    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: fill,
        shape: BoxShape.circle,
        border: Border.all(color: ring, width: 2),
        boxShadow: [
          if (isCurrent)
            BoxShadow(
              color: _accent.withValues(alpha: glow),
              blurRadius: 10,
              spreadRadius: 1,
            ),
        ],
      ),
      child: reached
          ? const Icon(Icons.check_rounded, size: 12, color: Colors.white)
          : null,
    );
  }

  Widget _timelineLine({required bool reached, required bool isCurrent}) {
    final Color c = reached ? _accent : _line;
    final double glow = isCurrent ? (_pulse ? 0.22 : 0.08) : 0.0;

    return Container(
      width: 4,
      height: 28,
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: c,
        borderRadius: BorderRadius.circular(99),
        boxShadow: [
          if (isCurrent)
            BoxShadow(
              color: _accent.withValues(alpha: glow),
              blurRadius: 10,
              spreadRadius: 1,
            ),
        ],
      ),
    );
  }

  // ---------------- Ticket / receipt (Progress) ----------------
  // The task rendered as a physical ticket: a receipt header, a perforated
  // tear line with punched side-notches, then the live progress thread. Makes
  // the tracking screen feel like a real-world handoff, not a status list.
  Widget _ticketCard({required Widget child, String? ticketId}) {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: AppRadii.bannerR,
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
              children: [
                Icon(
                  Icons.confirmation_number_outlined,
                  size: 16,
                  color: _accent,
                ),
                const SizedBox(width: 8),
                const Text(
                  'TASK TICKET',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    color: _muted,
                  ),
                ),
                const Spacer(),
                if (ticketId != null && ticketId.isNotEmpty)
                  Text(
                    '#$ticketId',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                      letterSpacing: 0.5,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
              ],
            ),
          ),
          _perforation(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: child,
          ),
        ],
      ),
    );
  }

  // A tear line: dashed perforation across the card with a cream notch
  // punched into each edge, so the header reads as a detachable stub.
  Widget _perforation() {
    return SizedBox(
      height: 18,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 16,
            right: 16,
            top: 0,
            bottom: 0,
            child: CustomPaint(painter: _DashedLinePainter(color: _line)),
          ),
          Positioned(left: -9, child: _notch()),
          Positioned(right: -9, child: _notch()),
        ],
      ),
    );
  }

  Widget _notch() => Container(
    width: 18,
    height: 18,
    decoration: BoxDecoration(
      color: _bg,
      shape: BoxShape.circle,
      border: Border.all(color: _line),
    ),
  );

  // ---------------- Small UI helpers ----------------
  Widget _softCard({required Widget child}) {
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
      child: child,
    );
  }

  Widget _pill({
    required IconData icon,
    required String label,
    required Color tint,
    required Color fg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SUPPORT BOTTOM SHEET
// ---------------------------------------------------------------------------

class _SupportSheet extends StatefulWidget {
  final String taskId;
  const _SupportSheet({required this.taskId});

  @override
  State<_SupportSheet> createState() => _SupportSheetState();
}

class _SupportSheetState extends State<_SupportSheet> {
  // Shared tokens — see lib/core/theme/app_theme.dart
  static const Color _accent = AppColors.saffron;
  static const Color _ink = AppColors.ink;
  static const Color _muted = AppColors.muted;
  static const Color _border = AppColors.divider;
  static const Color _surface = AppColors.surfaceMuted;

  static const List<String> _chips = [
    'Crew late',
    'Task issue',
    'Payment',
    'Safety',
    'Other',
  ];

  String? _selectedChip;
  final _messageCtrl = TextEditingController();
  bool _sending = false;
  List<Map<String, dynamic>> _requests = [];
  bool _loadingRequests = false;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRequests() async {
    setState(() => _loadingRequests = true);
    try {
      final list = await ApiService.getSupportRequestsForTask(widget.taskId);
      if (mounted) setState(() => _requests = list);
    } catch (_) {
      // silent — compose form still shown
    } finally {
      if (mounted) setState(() => _loadingRequests = false);
    }
  }

  bool get _canSend => _messageCtrl.text.trim().isNotEmpty && !_sending;

  Future<void> _send() async {
    final msg = _messageCtrl.text.trim();
    if (msg.isEmpty || _sending) return;
    setState(() => _sending = true);
    var success = false;
    try {
      await ApiService.createSupportRequest(
        widget.taskId,
        subject: _selectedChip,
        message: msg,
      );
      success = true;
      if (!mounted) return;
      _messageCtrl.clear();
      setState(() => _selectedChip = null);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks — our team will review this.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Something went wrong. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
    if (success && mounted) await _loadRequests();
  }

  Widget _statusBadge(String status) {
    final String label;
    final Color bg;
    final Color fg;
    switch (status) {
      case 'open':
        label = 'Open';
        bg = const Color(0xFFFEF3C7);
        fg = _accent;
        break;
      case 'in_progress':
        label = 'In progress';
        bg = const Color(0xFFDBEAFE);
        fg = const Color(0xFF1D4ED8);
        break;
      case 'resolved':
        label = 'Resolved';
        bg = const Color(0xFFDCFCE7);
        fg = const Color(0xFF16A34A);
        break;
      default:
        label = status;
        bg = _surface;
        fg = _muted;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }

  Widget _buildHistory() {
    if (_loadingRequests) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    if (_requests.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        for (final req in _requests)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (req['subject'] != null &&
                        (req['subject'] as String).isNotEmpty) ...[
                      Text(
                        req['subject'] as String,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                          color: _ink,
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    _statusBadge((req['status'] as String?) ?? 'open'),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  (req['message'] as String?) ?? '',
                  style: const TextStyle(fontSize: 13.5, color: _ink),
                ),
                const SizedBox(height: 10),
                if (req['admin_response'] != null &&
                    (req['admin_response'] as String).isNotEmpty) ...[
                  const Text(
                    'Our team replied',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: _accent,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    req['admin_response'] as String,
                    style: const TextStyle(fontSize: 13.5, color: _ink),
                  ),
                ] else
                  const Text(
                    'Support has received your request. Our team will review this.',
                    style: TextStyle(fontSize: 13, color: _muted),
                  ),
              ],
            ),
          ),
        const Divider(height: 28),
        const Text(
          'Send another request',
          style: TextStyle(fontSize: 13.5, color: _muted),
        ),
        const SizedBox(height: 14),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.fromLTRB(20, 0, 20, bottom + 24),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 18),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),

              const Text(
                'Need help?',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: _ink,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Support for this task',
                style: TextStyle(fontSize: 13.5, color: _muted),
              ),
              const SizedBox(height: 18),

              // History
              _buildHistory(),

              // Category chips
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _chips.map((chip) {
                  final selected = _selectedChip == chip;
                  return GestureDetector(
                    onTap: () =>
                        setState(() => _selectedChip = selected ? null : chip),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: selected ? const Color(0xFFFEF3C7) : _surface,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: selected ? _accent : _border,
                          width: selected ? 1.5 : 1.0,
                        ),
                      ),
                      child: Text(
                        chip,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: selected ? _accent : _ink,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Message field
              TextField(
                controller: _messageCtrl,
                onChanged: (_) => setState(() {}),
                maxLines: 4,
                maxLength: 4000,
                decoration: InputDecoration(
                  hintText: 'Tell us what happened…',
                  hintStyle: const TextStyle(color: _muted),
                  counterText: '',
                  filled: true,
                  fillColor: _surface,
                  contentPadding: const EdgeInsets.all(14),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: _ink, width: 1.5),
                  ),
                  suffixIcon: IconButton(
                    icon: const Icon(
                      Icons.keyboard_hide_rounded,
                      color: _muted,
                      size: 20,
                    ),
                    onPressed: () => FocusScope.of(context).unfocus(),
                    tooltip: 'Dismiss keyboard',
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Send button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _canSend ? _send : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    disabledBackgroundColor: _border,
                    disabledForegroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : const Text(
                          'Send to support',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 15.5,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Horizontal dashed line — the ticket's perforation / tear guide.
class _DashedLinePainter extends CustomPainter {
  final Color color;
  const _DashedLinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    const dash = 5.0;
    const gap = 5.0;
    final y = size.height / 2;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, y), Offset(x + dash, y), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter old) => old.color != color;
}
