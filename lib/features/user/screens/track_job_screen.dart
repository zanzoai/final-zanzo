// lib/features/user/screens/track_job_screen.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zanzo_frontend/core/services/api_service.dart';
import 'package:zanzo_frontend/core/services/task_events_ws_service.dart';
import 'package:zanzo_frontend/features/common/chat/chat_screen.dart';

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

  // ---------------- Theme tokens ----------------
  static const Color _accent = Color(
    0xFFD97706,
  ); // saffron — matches home/review
  static const Color _bg = Color(0xFFFCFAF6); // warm off-white
  static const Color _surface = Color(
    0xFFF5F2EE,
  ); // warm surface for pills/badges
  static const Color _card = Colors.white;
  static const Color _ink = Color(0xFF26211C); // warm charcoal
  static const Color _muted = Color(0xFF8C8378); // warm muted
  static const Color _line = Color(0xFFE8E2D9); // warm divider
  static const Color _success = Color(0xFF16A34A); // green — completed only
  static const Color _warning = Color(0xFFF59E0B); // amber — in-progress

  @override
  void initState() {
    super.initState();
    _assignedCrew = widget.assignedCrew;

    _pulseTimer = Timer.periodic(const Duration(milliseconds: 900), (_) {
      if (!mounted) return;
      setState(() => _pulse = !_pulse);
    });

    if (widget.jobId != null && widget.jobId!.isNotEmpty) {
      _fetchCurrentStatus();
      _startPolling();
      _startWs(widget.jobId!);
      _loadSession();
    } else {
      _startProgressSimulation();
    }
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
      }
    } catch (e) {
      debugPrint('[track] assignee fetch error: $e');
    }
  }

  Future<String?> _resolveViewerUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id');
  }

  Future<void> _openChat() async {
    final viewerUserId = await _resolveViewerUserId();
    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          jobId: widget.jobId ?? '',
          jobTitle: widget.taskTitle,
          viewerUserId: viewerUserId,
        ),
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
    _simTimer?.cancel();
    _pollTimer?.cancel();
    _pulseTimer?.cancel();
    _sessionTimer?.cancel();
    _wsTask?.dispose();
    super.dispose();
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
              currentStage >= 1)
            IconButton(
              tooltip: "Get help",
              icon: const Icon(Icons.help_outline_rounded),
              onPressed: _openSupportSheet,
            ),
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
    final Color tint = isTaskComplete ? const Color(0xFFE8F5E9) : _surface;
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
  Widget _agentCard() {
    final crew = _assignedCrew;
    final name = _titleCase((crew?['name'] ?? '').toString());
    final hasName = name.trim().isNotEmpty;

    return _softCard(
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
                            ? "Verified partner"
                            : "Assigning a partner soon",
                        style: TextStyle(fontSize: 13.5, color: _muted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: "Message",
                  onPressed: _openChat,
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                  color: _ink,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _pill(
                  icon: Icons.star_rounded,
                  label: "4.6",
                  tint: const Color(0xFFFFF3E9),
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
        ? const Color(0xFFE8F5E9)
        : (isActive ? const Color(0xFFFFF3E9) : _surface);

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

    return _softCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
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
      ),
    );
  }

  Widget _timelineNode({required bool reached, required bool isCurrent}) {
    final Color ring = reached
        ? _accent
        : const Color(0xFFE8E2D9); // _line equivalent
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
  static const Color _accent = Color(0xFFD97706);
  static const Color _ink = Color(0xFF26211C);
  static const Color _muted = Color(0xFF9B8B7E);
  static const Color _border = Color(0xFFE8E2D9);
  static const Color _surface = Color(0xFFF5F2EE);

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
        fg = const Color(0xFFD97706);
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
