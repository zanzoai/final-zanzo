// lib/features/user/screens/track_job_screen.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
// Core services
import 'package:zanzo_frontend/core/services/api_service.dart';
// User feature screens
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
  StreamSubscription<List<Map<String, dynamic>>>? _sub;
  Timer? _simTimer;
  Timer? _pollTimer;
  Timer? _sessionTimer;

  // Subtle pulse for current stage (tiny, premium)
  Timer? _pulseTimer;
  bool _pulse = false;

  Map<String, dynamic>? _assignedCrew;

  // ---------------- Theme tokens ----------------
  static const Color _brand = Color(0xFF6C4DFF); // use your brand purple
  static const Color _bg = Color(0xFFF6F7FB);
  static const Color _text = Color(0xFF111827);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _success = Color(0xFF16A34A);
  static const Color _warning = Color(0xFFF59E0B);

  @override
  void initState() {
    super.initState();
    _assignedCrew = widget.assignedCrew;

    _pulseTimer = Timer.periodic(const Duration(milliseconds: 1100), (_) {
      if (!mounted) return;
      setState(() => _pulse = !_pulse);
    });

    if (widget.jobId != null && widget.jobId!.isNotEmpty) {
      _fetchCurrentStatus();
      _startRealtime();
      _startPolling();

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
      final supabase = Supabase.instance.client;
      final res = await supabase
          .from('jobs')
          .select('status')
          .eq('id', widget.jobId!)
          .maybeSingle();

      if (res != null) {
        final st = (res['status'] as String?) ?? '';
        _updateStageFromStatus(st);

        // One-time fetch duration_hours
        try {
          if (_durationMinutes == 0) {
            final url = Uri.parse("${ApiService.baseUrl}/tasks/${widget.jobId}");
            final httpRes = await http.get(url, headers: await ApiService.authHeaders());
            if (httpRes.statusCode == 200) {
              final m = json.decode(httpRes.body) as Map<String, dynamic>;
              final d = m['duration_hours'];
              if (d is num && mounted) {
                setState(() => _durationMinutes = (d * 60).round());
              }
            }
          }
        } catch (_) {}

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

  void _startRealtime() {
    final supabase = Supabase.instance.client;
    _sub = supabase
        .from('jobs')
        .stream(primaryKey: ['id'])
        .eq('id', widget.jobId!)
        .listen(
          (rows) async {
            if (rows.isEmpty) return;

            final latest = rows.last;
            final newStatus = latest['status'];
            final oldStage = currentStage;

            _updateStageFromStatus(newStatus);

            final norm = _normalize(newStatus);
            if (_isAtOrAfterAssigned(norm) && oldStage < 1) {
              await _ensureAssigneeFetched();
            }
          },
          onError: (_) {
            _cancelRealtime();
          },
        );
  }

  void _startPolling() {
    _pollTimer?.cancel();

    // (Optional performance note): 1500ms is aggressive. Premium apps usually poll 3–5s.
    // Keeping your frequency for now; you can bump later safely.
    _pollTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) async {
      if (!mounted || widget.jobId == null || widget.jobId!.isEmpty) return;

      try {
        final url = Uri.parse("${ApiService.baseUrl}/tasks/${widget.jobId}");
        final res = await http.get(url, headers: await ApiService.authHeaders());
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
    } catch (_) {}
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
  }

  Future<void> _cancelJob() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel job?'),
        content: const Text(
          'Your payment will be released and the job will be cancelled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep job'),
          ),
          TextButton(
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel job'),
          ),
        ],
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
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cancel failed: ${res.body}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cancel failed: $e')),
      );
    }
  }

  void _cancelRealtime() {
    _sub?.cancel();
    _sub = null;
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
    _cancelRealtime();
    _sessionTimer?.cancel();
    super.dispose();
  }

  // ---------------- UI ----------------
  @override
  Widget build(BuildContext context) {
    final isTaskComplete = currentStage == baseStages.length - 1;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text("Live tracking"),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: _text,
        elevation: 0.6,
        actions: [
          IconButton(
            tooltip: "Refresh",
            icon: _loading
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
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
                  style: const TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                    color: _text,
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
          style: const TextStyle(
            fontSize: 20.5,
            fontWeight: FontWeight.w800,
            color: _text,
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
    final Color tint = isTaskComplete
        ? const Color(0xFFE8F5E9)
        : const Color(0xFFF3F4F6);
    final Color dot = isTaskComplete ? _success : _brand;

    return Container(
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black.withOpacity(0.05)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: _text,
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
            child: const Text("Update"),
          ),
        ],
      ),
    );
  }

  String _currentStatusLabel() {
    // Make it feel human and reassuring
    switch (currentStage) {
      case 0:
        return "Looking for a nearby ZenCrew partner";
      case 1:
        return "A ZenCrew partner accepted your job";
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
                  backgroundColor: _brand.withOpacity(0.12),
                  child: Text(
                    hasName ? name.characters.first.toUpperCase() : 'Z',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _brand,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasName ? name : "ZenCrew partner",
                        style: const TextStyle(
                          fontSize: 16.8,
                          fontWeight: FontWeight.w800,
                          color: _text,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasName
                            ? "Verified partner"
                            : "Assigning a partner soon",
                        style: const TextStyle(fontSize: 13.5, color: _muted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: "Message",
                  onPressed: _openChat,
                  icon: const Icon(Icons.chat_bubble_outline_rounded),
                  color: _brand,
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
                  tint: const Color(0xFFFFF7ED),
                  fg: _warning,
                ),
                _pill(
                  icon: Icons.verified_rounded,
                  label: "Bank",
                  tint: const Color(0xFFF3F4F6),
                  fg: _muted,
                ),
                _pill(
                  icon: Icons.verified_rounded,
                  label: "KYC",
                  tint: const Color(0xFFF3F4F6),
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
    final isActive = (_startConfirmedAt != null && _endConfirmedAt == null);
    final isCompleted = (_endConfirmedAt != null);

    String minsLabel() {
      if (_minutesWorked > 0) return '$_minutesWorked min';
      if (_startConfirmedAt != null && _endConfirmedAt == null) return 'Live';
      return '--';
    }

    final badgeText = isCompleted
        ? "Completed"
        : (isActive ? "In progress" : "Not started");
    final badgeColor = isCompleted ? _success : (isActive ? _warning : _muted);
    final badgeBg = isCompleted
        ? const Color(0xFFE8F5E9)
        : (isActive ? const Color(0xFFFFF7ED) : const Color(0xFFF3F4F6));

    return _softCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.lock_outline_rounded, color: _brand, size: 20),
                const SizedBox(width: 8),
                const Text(
                  "Job PINs",
                  style: TextStyle(
                    fontSize: 16.2,
                    fontWeight: FontWeight.w900,
                    color: _text,
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
                    border: Border.all(color: badgeColor.withOpacity(0.25)),
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
            const SizedBox(height: 12),

            _pinRow(
              label: "Start PIN",
              value: hasStart ? _startPin! : "—",
              verified: _startPinUsed,
              help: "Share when partner arrives",
              emphasize: hasStart,
            ),
            const SizedBox(height: 10),
            _pinRow(
              label: "End PIN",
              value: endShown ? _endPin! : "—",
              verified: _endPinUsed,
              help: endShown ? "Share on completion" : "Visible after start",
              emphasize: endShown,
            ),

            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.timer_outlined, size: 18, color: _muted),
                const SizedBox(width: 6),
                Text(
                  "Time: ${minsLabel()}",
                  style: const TextStyle(
                    fontSize: 13.8,
                    fontWeight: FontWeight.w700,
                    color: _text,
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: _text,
                ),
              ),
              const SizedBox(height: 4),
              Text(help, style: const TextStyle(fontSize: 12.5, color: _muted)),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Row(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: emphasize ? 18 : 15,
                fontWeight: emphasize ? FontWeight.w900 : FontWeight.w700,
                color: emphasize ? _text : _muted,
                letterSpacing: emphasize ? 2.0 : 0.2,
                fontFeatures: emphasize
                    ? const [FontFeature.tabularFigures()]
                    : const [],
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
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: _text,
                  ),
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
                backgroundColor: Colors.black.withOpacity(0.06),
                valueColor: const AlwaysStoppedAnimation<Color>(_brand),
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

    return _softCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Column(
          children: List.generate(stages.length, (i) {
            final reached = i < currentStage;
            final isCurrent = i == currentStage;

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
                            ? _text
                            : isCurrent
                            ? _text
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
    final Color ring = reached ? _brand : Colors.black.withOpacity(0.18);
    final Color fill = reached ? _brand : Colors.white;

    final double glow = isCurrent ? (_pulse ? 0.22 : 0.10) : 0.0;

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
              color: _brand.withOpacity(glow),
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
    final Color c = reached ? _brand : Colors.black.withOpacity(0.12);
    final double glow = isCurrent ? (_pulse ? 0.18 : 0.08) : 0.0;

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
              color: _brand.withOpacity(glow),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
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
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: _text,
            ),
          ),
        ],
      ),
    );
  }
}
