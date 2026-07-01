// -----------------------------------------------------------------------------
// ZanCrew — JOB DETAIL (Crew side)
//
// PREMIUM UI REFINEMENT (frontend only)
// ✅ Backend untouched
// ✅ Existing features preserved: chat, realtime, timer summary, status flow,
//    start/end PIN loops, postJobEvent with crew_user_id, pop(true) on complete.
// -----------------------------------------------------------------------------
//
// Data sources:
//   • GET  /jobs/{job_id}           → full job snapshot (+ last_event)
//   • GET  /jobs/{job_id}/session   → time summary (minutes_worked, is_active)
//   • POST /jobs/{job_id}/events    → status updates (assigned/travelling/arrived/...)
//   • POST /jobs/{job_id}/session/start  → start session with PIN
//   • POST /jobs/{job_id}/session/end    → end session with PIN
//
// File: lib/features/zancrew/screens/zancrew_JobDetails.dart
// -----------------------------------------------------------------------------

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zanzo_frontend/features/common/chat/chat_screen.dart';

import '../../../core/services/api_service.dart';
import '../../../core/widgets/payment_chip.dart';

class CrewJobDetail extends StatefulWidget {
  final String jobId;
  const CrewJobDetail({super.key, required this.jobId});

  @override
  State<CrewJobDetail> createState() => _CrewJobDetailState();
}

class _CrewJobDetailState extends State<CrewJobDetail> {
  bool _loading = true;
  bool _posting = false;

  Map<String, dynamic>? _job; // full job snapshot from /jobs/{id}
  Map<String, dynamic>? _lastEvent; // last job_event

  // --- session summary (timer/progress) ---
  Timer? _summaryTimer;
  int _minutesWorked = 0;
  bool _sessionActive = false;
  RealtimeChannel? _jobEventsChannel;

  // Accepted job flow
  static const List<String> _flow = [
    'assigned',
    'travelling',
    'arrived',
    'in_progress',
    'completed',
  ];

  // Warm Zanzo palette
  static const Color _accent = Color(0xFFD97706);
  static const Color _bg = Color(0xFFFCFAF6);
  static const Color _surface = Color(0xFFF5F2EE);
  static const Color _card = Colors.white;
  static const Color _ink = Color(0xFF26211C);
  static const Color _muted = Color(0xFF9B8B7E);
  static const Color _border = Color(0xFFE8E2D9);
  static const Color _success = Color(0xFF16A34A);

  @override
  void initState() {
    super.initState();
    _loadJob();

    // Prime the time summary once, then refresh every 30s
    _refreshSessionSummary();
    _listenToJobEvents();
    _summaryTimer?.cancel();
    _summaryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      _refreshSessionSummary();
    });
  }

  @override
  void dispose() {
    _jobEventsChannel?.unsubscribe();
    _summaryTimer?.cancel();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  //  USER ID → for chat
  // ---------------------------------------------------------------------------

  Future<String?> _resolveViewerUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id'); // crew's profiles.id
  }

  Future<void> _openChat() async {
    final viewerUserId = await _resolveViewerUserId();
    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          jobId: widget.jobId,
          jobTitle: (_job?['title'] ?? 'Chat').toString(),
          viewerUserId: viewerUserId,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  //  LOAD JOB SNAPSHOT
  // ---------------------------------------------------------------------------

  Future<void> _loadJob() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.getJson('/tasks/${widget.jobId}');
      if (!mounted) return;

      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded is Map) {
          final data = Map<String, dynamic>.from(
            decoded.map((k, v) => MapEntry(k.toString(), v)),
          );

          setState(() {
            _job = data;
            final le = data['last_event'];
            _lastEvent = (le is Map)
                ? le.map((k, v) => MapEntry(k.toString(), v))
                : null;
          });
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load job: HTTP ${res.statusCode}')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to load job: $e')));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------------------------------------------------------------------------
  //  TIME SUMMARY (minutes worked, active flag)
  // ---------------------------------------------------------------------------

  Future<void> _refreshSessionSummary() async {
    try {
      final s = await ApiService.getSessionSummary(widget.jobId);
      if (!mounted) return;

      final minutes = s['minutes_worked'];
      final isActive = s['is_active'];

      setState(() {
        _minutesWorked = (minutes is int) ? minutes : 0;
        _sessionActive = isActive == true;
      });
    } catch (_) {
      // ignore errors; next periodic tick will retry
    }
  }

  // ---------------------------------------------------------------------------
  //  REALTIME JOB EVENTS LISTENER
  // ---------------------------------------------------------------------------

  void _listenToJobEvents() {
    final supabase = Supabase.instance.client;

    _jobEventsChannel = supabase
        .channel('job-events-${widget.jobId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'job_events',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'job_id',
            value: widget.jobId,
          ),
          callback: (payload) {
            if (!mounted) return;
            _loadJob();
            _refreshSessionSummary();
          },
        )
        .subscribe();
  }

  // ---------------------------------------------------------------------------
  //  STATUS HELPERS
  // ---------------------------------------------------------------------------

  String _currentStatus() {
    final s = (_job?['status'] ?? '').toString().toLowerCase();
    if (s.isNotEmpty) return s;
    final e = (_lastEvent?['status'] ?? '').toString().toLowerCase();
    return e.isNotEmpty ? e : 'assigned';
  }

  String? _nextStatus() {
    final cur = _currentStatus();
    final idx = _flow.indexOf(cur);
    if (idx == -1) return 'travelling';
    if (idx >= _flow.length - 1) return null;
    return _flow[idx + 1];
  }

  String _pretty(String s) {
    switch (s) {
      case 'in_progress':
        return 'In progress';
      default:
        return s
            .replaceAll('_', ' ')
            .split(' ')
            .map((w) => w.isEmpty ? w : (w[0].toUpperCase() + w.substring(1)))
            .join(' ');
    }
  }

  String _actionLabel(String s) {
    switch (s) {
      case 'travelling':
        return "I'm Travelling";
      case 'arrived':
        return "I've Arrived";
      case 'in_progress':
        return "Start Job";
      case 'completed':
        return "Mark Complete";
      default:
        return 'Update';
    }
  }

  // ---------------------------------------------------------------------------
  //  DISPLAY HELPERS
  // ---------------------------------------------------------------------------

  String _whenLabel() {
    final raw = (_job?['scheduled_at'] ?? '').toString();
    return raw; // ISO string (can be formatted later if needed)
  }

  String _priceLabel() {
    final currency = (_job?['currency'] ?? '').toString().toUpperCase();
    final amount = _job?['estimated_amount'];
    if (amount != null) {
      try {
        final v = (amount is num)
            ? amount.toDouble()
            : double.parse(amount.toString());
        final symbol = (currency == 'GBP')
            ? '£'
            : (currency == 'INR')
            ? '₹'
            : '£';
        final isWhole = v.truncateToDouble() == v;
        return '$symbol${v.toStringAsFixed(isWhole ? 0 : 2)} est.';
      } catch (_) {}
    }
    return '';
  }

  List<String> _strList(dynamic v) {
    if (v is List) {
      return v
          .map((e) => e.toString())
          .where((s) => s.trim().isNotEmpty)
          .toList();
    }
    return const [];
  }

  List<String> _importantNotes() {
    final n = _job?['notes'];
    if (n is List) return _strList(n);
    if (n is String && n.trim().isNotEmpty) {
      return n
          .split(',')
          .map((e) => e.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    }
    return const [];
  }

  // ---------------------------------------------------------------------------
  //  BACKEND EVENT CALLS  (PATCHED to SEND crew_user_id)
  // ---------------------------------------------------------------------------

  Future<void> _sendProgress(String status, {String? note}) async {
    setState(() => _posting = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final crewUserId = prefs.getString("user_id");

      if (crewUserId == null) {
        throw Exception("Missing crew_user_id in SharedPreferences");
      }

      await ApiService.postJobEvent(
        widget.jobId,
        status,
        note ?? "",
        crewUserId,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Marked as ${_pretty(status)}')));

      await _loadJob();
      // Force status — Redis may serve stale data for up to 60s after event POST
      if (mounted && _job != null) setState(() => _job!['status'] = status);

      // notify earnings screen it should refresh
      if (status == 'completed') {
        Navigator.of(context).pop(true); // return TRUE to parent to refresh
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Update failed: $e')));
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  // ---------------------------------------------------------------------------
  //  PIN FLOWS (START / END SESSION)
  // ---------------------------------------------------------------------------

  Future<void> _handleNextPressed(String status) async {
    // START → ask for Start PIN
    if (status == 'in_progress') {
      final controller = TextEditingController();
      String? errorText;

      while (true) {
        final pin = await showDialog<String>(
          context: context,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, setLocalState) {
              return AlertDialog(
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: const Text(
                  'Confirm start',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Ask the customer for their 4-digit Start PIN.',
                      style: TextStyle(color: _muted),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      decoration: InputDecoration(
                        hintText: 'Enter 4-digit PIN',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        fillColor: _surface,
                        filled: true,
                        errorText: errorText,
                      ),
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () =>
                        Navigator.of(ctx).pop(controller.text.trim()),
                    child: const Text('Verify'),
                  ),
                ],
              );
            },
          ),
        );

        if (pin == null || pin.isEmpty) return;

        setState(() => _posting = true);
        try {
          await ApiService.postSessionStart(widget.jobId, pin);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Start PIN verified — job started')),
          );
          await _loadJob();
          if (mounted && _job != null)
            setState(() => _job!['status'] = 'in_progress');
          return; // success → exit loop
        } catch (_) {
          errorText = "Wrong PIN, please try again";
          controller.clear();
        } finally {
          if (mounted) setState(() => _posting = false);
        }
      }
    }

    // COMPLETE → ask for End PIN
    if (status == 'completed') {
      final controller = TextEditingController();
      String? errorText;

      while (true) {
        final pin = await showDialog<String>(
          context: context,
          builder: (ctx) => StatefulBuilder(
            builder: (ctx, setLocalState) {
              return AlertDialog(
                backgroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: const Text(
                  'Confirm completion',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Ask the customer for their 4-digit End PIN.',
                      style: TextStyle(color: _muted),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      decoration: InputDecoration(
                        hintText: 'Enter 4-digit PIN',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        fillColor: _surface,
                        filled: true,
                        errorText: errorText,
                      ),
                      keyboardType: TextInputType.number,
                      maxLength: 4,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: () =>
                        Navigator.of(ctx).pop(controller.text.trim()),
                    child: const Text('Verify'),
                  ),
                ],
              );
            },
          ),
        );

        if (pin == null || pin.isEmpty) return;

        setState(() => _posting = true);
        try {
          await ApiService.postSessionEnd(widget.jobId, pin);
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('End PIN verified — job completed ✅')),
          );
          await _loadJob();
          if (mounted && _job != null)
            setState(() => _job!['status'] = 'completed');
          Navigator.of(context).pop(true);
          return; // success → exit loop
        } catch (_) {
          errorText = "Wrong PIN, please try again";
          controller.clear();
        } finally {
          if (mounted) setState(() => _posting = false);
        }
      }
    }

    // OTHER STATUSES → normal job events
    await _sendProgress(status);
  }

  // ---------------------------------------------------------------------------
  //  PREMIUM UI HELPERS
  // ---------------------------------------------------------------------------

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w800,
        color: _ink,
      ),
    );
  }

  Widget _softCard({required Widget child, EdgeInsets? padding}) {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      padding: padding ?? const EdgeInsets.all(14),
      child: child,
    );
  }

  Color _statusAccent(String status) {
    switch (status) {
      case 'assigned':
        return const Color(0xFF2563EB); // blue
      case 'travelling':
      case 'traveling':
      case 'en_route':
        return const Color(0xFFF59E0B); // amber
      case 'arrived':
        return const Color(0xFF10B981); // green
      case 'in_progress':
        return _ink;
      case 'completed':
        return _success;
      default:
        return const Color(0xFF6B7280);
    }
  }

  IconData _statusIcon(String status) {
    switch (status) {
      case 'assigned':
        return Icons.assignment_outlined;
      case 'travelling':
      case 'traveling':
      case 'en_route':
        return Icons.navigation_outlined;
      case 'arrived':
        return Icons.location_on_outlined;
      case 'in_progress':
        return Icons.build_circle_outlined;
      case 'completed':
        return Icons.verified_outlined;
      default:
        return Icons.info_outline;
    }
  }

  Widget _statusHeader({
    required String status,
    required String title,
    required String price,
    required Widget? paymentChip,
  }) {
    final accent = _statusAccent(status);

    return _softCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status pill
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_statusIcon(status), size: 16, color: accent),
                    const SizedBox(width: 6),
                    Text(
                      _pretty(status),
                      style: TextStyle(
                        color: accent,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (paymentChip != null) paymentChip,
            ],
          ),

          const SizedBox(height: 12),

          // Price (anchoring value)
          if (price.isNotEmpty)
            Text(
              price,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                letterSpacing: -0.6,
                color: _ink,
              ),
            ),

          const SizedBox(height: 6),

          // Title
          Text(
            title.isEmpty ? 'Active job' : title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              height: 1.15,
              color: _ink,
            ),
          ),

          const SizedBox(height: 10),

          // Micro line: “You are in control”
          const Text(
            'Keep the job updated as you move.',
            style: TextStyle(
              color: _muted,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _locationCard({required String addr, required String when}) {
    if (addr.isEmpty && when.isEmpty) return const SizedBox.shrink();

    return _softCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Location'),
          const SizedBox(height: 10),
          if (when.isNotEmpty)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Icon(Icons.schedule, size: 18, color: _muted),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Scheduled time shown above',
                    style: TextStyle(color: _muted),
                  ),
                ),
              ],
            ),
          if (when.isNotEmpty) const SizedBox(height: 10),
          if (addr.isNotEmpty)
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () {
                // No new dependency here. We keep compile-safe.
                // You can wire a proper map launcher later (url_launcher).
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Maps opening can be wired next.'),
                  ),
                );
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Icon(Icons.place_outlined, color: _muted),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Tap to open directions',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _ink,
                        ),
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios, size: 14, color: _muted),
                  ],
                ),
              ),
            ),
          if (addr.isNotEmpty) const SizedBox(height: 10),
          if (addr.isNotEmpty)
            Text(
              addr,
              style: const TextStyle(
                color: _muted,
                height: 1.35,
                fontSize: 13.5,
              ),
            ),
        ],
      ),
    );
  }

  Widget _metaRow({required IconData icon, required String label}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: _muted),
        const SizedBox(width: 8),
        Text(
          label,
          style: const TextStyle(color: _ink, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _detailsCard({
    required String desc,
    required dynamic duration,
    required dynamic people,
  }) {
    if (desc.isEmpty && duration == null && people == null) {
      return const SizedBox.shrink();
    }

    return _softCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Job details'),
          const SizedBox(height: 10),
          if (duration != null || people != null)
            Wrap(
              spacing: 16,
              runSpacing: 10,
              children: [
                if (duration != null)
                  _metaRow(
                    icon: Icons.timer_outlined,
                    label:
                        '$duration hour${(duration is num && duration == 1) ? '' : 's'}',
                  ),
                if (people != null)
                  _metaRow(
                    icon: Icons.people_alt_outlined,
                    label: 'People: $people',
                  ),
              ],
            ),
          if (duration != null || people != null) const SizedBox(height: 12),
          if (desc.isNotEmpty)
            Text(
              desc,
              style: const TextStyle(color: _ink, height: 1.5, fontSize: 14.5),
            ),
        ],
      ),
    );
  }

  Widget _actionsCard(List<String> actions) {
    if (actions.isEmpty) return const SizedBox.shrink();

    return _softCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Expected actions'),
          const SizedBox(height: 10),
          ...actions.map((a) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 3),
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF3C7),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: _border),
                    ),
                    child: const Icon(Icons.check, size: 14, color: _accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      a,
                      style: const TextStyle(
                        color: _ink,
                        height: 1.4,
                        fontSize: 14.2,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          const Text(
            'Tip: Keep these steps in mind while working.',
            style: TextStyle(
              color: _muted,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _notesCard(List<String> notes) {
    if (notes.isEmpty) return const SizedBox.shrink();

    return _softCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Important notes'),
          const SizedBox(height: 10),
          ...notes.map((n) {
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Text(
                n,
                style: const TextStyle(
                  color: _ink,
                  height: 1.4,
                  fontSize: 13.8,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  Widget _tagsRow(List<String> tags) {
    if (tags.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: tags.map((t) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: _border),
          ),
          child: Text(
            t,
            style: const TextStyle(
              color: _ink,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _timeSummaryCard({required int durationMinutes}) {
    if (!((_sessionActive || _minutesWorked > 0) && durationMinutes > 0)) {
      return const SizedBox.shrink();
    }

    return _softCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Time summary'),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.timer_outlined, size: 18, color: _muted),
              const SizedBox(width: 8),
              Text(
                '${_minutesWorked}m / ${durationMinutes}m',
                style: const TextStyle(
                  color: _muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _sessionActive ? const Color(0xFFECFDF5) : _surface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _border),
                ),
                child: Text(
                  _sessionActive ? 'Tracking' : 'Stopped',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: _sessionActive ? _success : _muted,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (_minutesWorked / durationMinutes).clamp(0.0, 1.0),
              minHeight: 9,
              backgroundColor: _border,
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFF22C55E),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _sessionActive
                ? 'Time is being tracked while you work.'
                : 'Session ended.',
            style: const TextStyle(
              fontSize: 12.5,
              color: _muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _progressTimeline(String status) {
    // We keep your chip logic but present it in a cleaner premium card.
    final activeIndex = _flow.indexOf(
      status == 'completed' ? 'completed' : status,
    );

    return _softCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Progress'),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _flow.map((s) {
              final chipIndex = _flow.indexOf(s);
              final active = chipIndex <= activeIndex;
              final accent = active ? _statusAccent(s) : _muted;

              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: active ? accent.withValues(alpha: 0.10) : _surface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _border),
                ),
                child: Text(
                  _pretty(s),
                  style: TextStyle(
                    color: active ? accent : _muted,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  void _showSupportSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CrewSupportSheet(taskId: widget.jobId),
    );
  }

  Widget _supportCta() {
    return GestureDetector(
      onTap: _showSupportSheet,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Text(
              'Need help with this job?',
              style: TextStyle(
                color: _muted,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Contact support',
              style: TextStyle(
                color: _ink,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                decoration: TextDecoration.underline,
                decorationColor: _ink,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomActionBar({required String status, required String? next}) {
    if (next == null) {
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: _border)),
        ),
        child: const SafeArea(
          top: false,
          child: Text(
            'This job is completed ✅',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _success,
              fontWeight: FontWeight.w800,
              fontSize: 14.5,
            ),
          ),
        ),
      );
    }

    final label = _actionLabel(next);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: _border)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _accent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: _posting ? null : () => _handleNextPressed(next),
                child: _posting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        label,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.2,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: _ink,
                side: const BorderSide(color: _border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                minimumSize: const Size(double.infinity, 48),
              ),
              icon: const Icon(Icons.refresh),
              label: const Text(
                'Refresh',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              onPressed: _loading ? null : _loadJob,
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  //  UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final Widget? paymentChip = PaymentChip.fromMap(_job ?? _lastEvent ?? {});

    if (_loading) {
      return Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          foregroundColor: _ink,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          title: const Text(
            'Active Job',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.2),
          ),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_job == null) {
      return Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          foregroundColor: _ink,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.transparent,
          title: const Text(
            'Active Job',
            style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.2),
          ),
        ),
        body: const Center(child: Text('Job not found')),
      );
    }

    final title = (_job!['title'] ?? '').toString();
    final desc = (_job!['polished_task'] ?? '').toString();
    final addr = (_job!['location_address'] ?? '').toString();
    final when = _whenLabel();
    final price = _priceLabel();

    final actions = _strList(_job!['actions']);
    final tags = _strList(_job!['tags']);
    final notes = _importantNotes();

    final duration = _job!['duration_hours'];
    final people = _job!['people_required'];

    final status = _currentStatus();
    final next = _nextStatus();

    // Chat becomes available once job is at least assigned
    final canChat = const {
      'assigned',
      'travelling',
      'traveling',
      'en_route',
      'arrived',
      'in_progress',
      'started',
      'completed',
    }.contains(status);

    // For time summary progress bar
    final int durationMinutes = () {
      final d = _job?['duration_hours'];
      if (d is num) return (d * 60).round();
      return 0;
    }();

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: _ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Active Job',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.2),
        ),
        actions: [
          if (canChat)
            IconButton(
              tooltip: 'Chat with customer',
              icon: const Icon(Icons.chat_bubble_outline),
              onPressed: _openChat,
            ),
        ],
      ),
      bottomNavigationBar: _bottomActionBar(status: status, next: next),
      body: RefreshIndicator(
        onRefresh: _loadJob,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
          children: [
            _statusHeader(
              status: status,
              title: title.isEmpty ? 'Active job' : title,
              price: price,
              paymentChip: paymentChip,
            ),
            const SizedBox(height: 12),

            _locationCard(addr: addr, when: when),
            const SizedBox(height: 12),

            _detailsCard(desc: desc, duration: duration, people: people),
            const SizedBox(height: 12),

            _actionsCard(actions),
            if (actions.isNotEmpty) const SizedBox(height: 12),

            _notesCard(notes),
            if (notes.isNotEmpty) const SizedBox(height: 12),

            if (tags.isNotEmpty)
              _softCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sectionTitle('Tags'),
                    const SizedBox(height: 10),
                    _tagsRow(tags),
                  ],
                ),
              ),
            if (tags.isNotEmpty) const SizedBox(height: 12),

            _timeSummaryCard(durationMinutes: durationMinutes),
            if ((_sessionActive || _minutesWorked > 0) && durationMinutes > 0)
              const SizedBox(height: 12),

            _progressTimeline(status),
            const SizedBox(height: 24),

            Center(child: _supportCta()),
            const SizedBox(height: 90), // space for bottom bar
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// CREW SUPPORT BOTTOM SHEET
// ---------------------------------------------------------------------------

class _CrewSupportSheet extends StatefulWidget {
  final String taskId;
  const _CrewSupportSheet({required this.taskId});

  @override
  State<_CrewSupportSheet> createState() => _CrewSupportSheetState();
}

class _CrewSupportSheetState extends State<_CrewSupportSheet> {
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
