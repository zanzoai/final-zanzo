import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:zanzo_frontend/core/services/api_service.dart';
import 'package:zanzo_frontend/features/user/screens/review_task_screen.dart';
import 'package:zanzo_frontend/features/user/screens/track_job_screen.dart';

class JobHistoryScreen extends StatefulWidget {
  const JobHistoryScreen({super.key});

  @override
  State<JobHistoryScreen> createState() => _JobHistoryScreenState();
}

class _JobHistoryScreenState extends State<JobHistoryScreen> {
  // Warm Zanzo palette
  static const Color _accent = Color(0xFFD97706);
  static const Color _bg = Color(0xFFFCFAF6);
  static const Color _surface = Color(0xFFF5F2EE);
  static const Color _card = Colors.white;
  static const Color _ink = Color(0xFF26211C);
  static const Color _muted = Color(0xFF8C8378);
  static const Color _line = Color(0xFFE8E2D9);
  static const Color _success = Color(0xFF16A34A);
  static const Color _warning = Color(0xFFF59E0B);

  List jobs = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchJobs();
  }

  Future<void> _fetchJobs() async {
    setState(() => isLoading = true);
    try {
      final res = await ApiService.getJson('/tasks/my');
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded is List) {
          setState(() => jobs = decoded);
        }
      }
    } catch (_) {
      // ignore
    } finally {
      setState(() => isLoading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _safeStr(dynamic v, [String fallback = '']) {
    if (v == null) return fallback;
    final s = v.toString().trim();
    return s.isEmpty ? fallback : s;
  }

  List<String> _safeStrList(dynamic v) {
    if (v is List) {
      return v
          .map((e) => e.toString())
          .where((e) => e.trim().isNotEmpty)
          .toList();
    }
    return const <String>[];
  }

  String _fmtDate(dynamic raw) {
    if (raw == null) return '';
    try {
      final dt = DateTime.tryParse(raw.toString())?.toLocal();
      if (dt == null) return raw.toString();
      return DateFormat('d MMM yyyy, h:mm a').format(dt);
    } catch (_) {
      return raw.toString();
    }
  }

  String _statusLabel(String raw) {
    final s = raw.toLowerCase();
    switch (s) {
      case 'payment_pending':
        return "Payment Pending";
      case 'searching':
      case 'finding_agent':
        return "Finding Agent";
      case 'assigned':
        return "Agent Assigned";
      case 'travelling':
      case 'traveling':
      case 'en_route':
        return "On the Way";
      case 'arrived':
        return "Arrived";
      case 'in_progress':
      case 'started':
        return "In Progress";
      case 'completed':
      case 'settled':
        return "Completed";
      case 'paid':
        return "Paid";
      case 'cancelled':
      case 'canceled':
        return "Cancelled";
      default:
        return raw.isEmpty ? "Unknown" : raw;
    }
  }

  ({Color bg, Color border, Color text}) _statusColors(String raw) {
    final s = raw.toLowerCase();

    if (s == 'completed' || s == 'settled' || s == 'paid') {
      return (
        bg: const Color(0xFFE8F5E9),
        border: const Color(0xFF66BB6A),
        text: const Color(0xFF2E7D32),
      );
    }

    if (s == 'cancelled' || s == 'canceled') {
      return (
        bg: const Color(0xFFFFEBEE),
        border: const Color(0xFFE57373),
        text: const Color(0xFFC62828),
      );
    }

    if (s == 'payment_pending') {
      return (
        bg: const Color(0xFFFFF3E9),
        border: _warning,
        text: _accent,
      );
    }

    if (s == 'searching' ||
        s == 'finding_agent' ||
        s == 'assigned' ||
        s == 'travelling' ||
        s == 'traveling' ||
        s == 'en_route' ||
        s == 'arrived' ||
        s == 'in_progress' ||
        s == 'started') {
      return (
        bg: const Color(0xFFFFF3E0),
        border: const Color(0xFFFFB74D),
        text: const Color(0xFFEF6C00),
      );
    }

    return (
      bg: const Color(0xFFF5F5F5),
      border: const Color(0xFFBDBDBD),
      text: const Color(0xFF616161),
    );
  }

  Widget _pill(String text, {required String rawStatus}) {
    final c = _statusColors(rawStatus);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: c.text,
        ),
      ),
    );
  }

  Widget _kvRow({required String icon, required String text}) {
    if (text.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Text(icon),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: TextStyle(color: _ink)),
          ),
        ],
      ),
    );
  }

  Widget _warmChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _line),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: _ink,
        ),
      ),
    );
  }

  bool _isCompletedStatus(String status) {
    final s = status.toLowerCase();
    return s == 'completed' ||
        s == 'settled' ||
        s == 'paid' ||
        s == 'cancelled' ||
        s == 'canceled';
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: const Text(
          "My Job History",
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: _bg,
        foregroundColor: _ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          IconButton(
            onPressed: isLoading ? null : _fetchJobs,
            icon: isLoading
                ? SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: _accent,
                    ),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : jobs.isEmpty
          ? _emptyState()
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: jobs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (context, index) =>
                  _jobCard(context, jobs[index] as Map<String, dynamic>),
            ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 56,
              color: _accent.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              "No orders yet",
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              "Your completed orders will appear here.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: _muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _jobCard(BuildContext context, Map<String, dynamic> job) {
    final jobId = _safeStr(job['id']);
    final backendConcise = _safeStr(job['concise_title']);

    final title = backendConcise.isNotEmpty
        ? backendConcise
        : _safeStr(
            job['title'],
            _safeStr(
              job['short_title'],
              _safeStr(job['polished_task'], 'Your Task'),
            ),
          );

    final created = _fmtDate(job['created_at']);
    final location = _safeStr(job['location_address']);
    final statusRaw = _safeStr(job['status']);
    final status = _statusLabel(statusRaw);

    final description = _safeStr(job['polished_task']);

    final notesAny = job['notes'];
    final notesList = _safeStrList(notesAny);
    final notesText = (notesAny is String) ? notesAny.trim() : '';

    final actions = _safeStrList(job['actions']);
    final tags = _safeStrList(job['tags']);

    final scheduled = _fmtDate(job['scheduled_at']);
    final completed = _fmtDate(job['completed_at']);
    final paidAt = _fmtDate(job['paid_at']);

    final duration = _safeStr(job['duration_hours']);
    final people = _safeStr(job['people_required']);

    final amount = job['estimated_amount'];
    final currency = _safeStr(job['currency'], 'GBP').toUpperCase();
    final symbol = currency == 'GBP'
        ? '£'
        : currency == 'INR'
        ? '₹'
        : currency;
    final cost = (amount is num)
        ? amount.toStringAsFixed(amount.truncateToDouble() == amount ? 0 : 2)
        : '';

    final isActive = !_isCompletedStatus(statusRaw);

    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                backgroundColor: _card,
                collapsedBackgroundColor: _card,
                tilePadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 6,
                ),
                childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                title: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700, color: _ink),
                ),
                subtitle: Text(
                  [
                    if (created.isNotEmpty) created,
                    if (location.isNotEmpty && location != 'Unknown address')
                      location,
                  ].join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
                trailing: _pill(status, rawStatus: statusRaw),
                children: [
                  if (description.isNotEmpty) ...[
                    Text(
                      "Requirements",
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      description,
                      style: TextStyle(height: 1.35, color: _ink),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (notesList.isNotEmpty || notesText.isNotEmpty) ...[
                    Text(
                      "Important Notes",
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (notesList.isNotEmpty)
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: notesList.map(_warmChip).toList(),
                      )
                    else
                      Text(
                        notesText,
                        style: TextStyle(height: 1.35, color: _ink),
                      ),
                    const SizedBox(height: 12),
                  ],
                  if (actions.isNotEmpty) ...[
                    Text(
                      "Expected Actions",
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: actions
                          .map(
                            (a) => Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text("•  ", style: TextStyle(color: _ink)),
                                  Expanded(
                                    child: Text(
                                      a,
                                      style: TextStyle(
                                        height: 1.35,
                                        color: _ink,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (tags.isNotEmpty) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: tags.map(_warmChip).toList(),
                    ),
                    const SizedBox(height: 12),
                  ],
                  _kvRow(icon: '📍', text: location),
                  _kvRow(
                    icon: '🕒',
                    text: created.isNotEmpty ? 'Ordered: $created' : '',
                  ),
                  _kvRow(
                    icon: '🗓️',
                    text: scheduled.isNotEmpty ? 'Scheduled: $scheduled' : '',
                  ),
                  _kvRow(
                    icon: '✅',
                    text: completed.isNotEmpty ? 'Completed: $completed' : '',
                  ),
                  _kvRow(
                    icon: '💳',
                    text: paidAt.isNotEmpty ? 'Paid at: $paidAt' : '',
                  ),
                  _kvRow(
                    icon: '⏱️',
                    text: duration.isNotEmpty
                        ? 'Duration: $duration hours'
                        : '',
                  ),
                  _kvRow(
                    icon: '👥',
                    text: people.isNotEmpty ? 'People Required: $people' : '',
                  ),
                  _kvRow(
                    icon: '💰',
                    text: cost.isNotEmpty ? 'Estimated: $symbol$cost' : '',
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerRight,
                    child: _isCompletedStatus(statusRaw)
                        ? ElevatedButton.icon(
                            icon: const Icon(Icons.refresh),
                            label: const Text("Request Again"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _success,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () {
                              final prefill = Map<String, dynamic>.from(job);

                              final anyNotes = prefill['notes'];
                              if (anyNotes is String) {
                                final chips = anyNotes
                                    .split(RegExp(r'\s*,\s*'))
                                    .map((e) => e.trim())
                                    .where((e) => e.isNotEmpty)
                                    .toList();
                                prefill['notes'] = chips;
                              }

                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => ReviewTaskScreen(
                                    taskType: title,
                                    taskDetail: prefill,
                                  ),
                                ),
                              );
                            },
                          )
                        : ElevatedButton.icon(
                            icon: const Icon(Icons.map_outlined),
                            label: const Text("Track Job"),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _accent,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: jobId.isEmpty
                                ? null
                                : () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => TrackJobScreen(
                                          taskTitle: title,
                                          userLocation: location.isNotEmpty
                                              ? location
                                              : 'Unknown location',
                                          jobId: jobId,
                                        ),
                                      ),
                                    );
                                  },
                          ),
                  ),
                ],
              ),
            ),
            // Quick track row — visible on the collapsed card for active jobs
            if (isActive && jobId.isNotEmpty) ...[
              Divider(height: 1, color: _line),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => TrackJobScreen(
                        taskTitle: title,
                        userLocation: location.isNotEmpty
                            ? location
                            : 'Unknown location',
                        jobId: jobId,
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 11,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.map_outlined, size: 15, color: _accent),
                        const SizedBox(width: 8),
                        Text(
                          "Track this job",
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _accent,
                          ),
                        ),
                        const Spacer(),
                        Icon(Icons.arrow_forward_ios, size: 12, color: _muted),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
