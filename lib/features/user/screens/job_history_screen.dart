// This screen fetches and displays the user’s full job history, showing each job in an expandable card with detailed information.
//It also allows users to either track an ongoing job or re-request a completed job with pre-filled details

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:zanzo_frontend/features/user/screens/review_task_screen.dart';
import 'package:zanzo_frontend/features/user/screens/track_job_screen.dart';

class JobHistoryScreen extends StatefulWidget {
  const JobHistoryScreen({super.key});

  @override
  State<JobHistoryScreen> createState() => _JobHistoryScreenState();
}

class _JobHistoryScreenState extends State<JobHistoryScreen> {
  List jobs = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchJobs();
  }

  Future<void> _fetchJobs() async {
    // No customer task history endpoint is available on this backend version.
    setState(() {
      jobs = [];
      isLoading = false;
    });
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
        bg: const Color(0xFFE3F2FD),
        border: const Color(0xFF64B5F6),
        text: const Color(0xFF1565C0),
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
          Expanded(child: Text(text)),
        ],
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
      appBar: AppBar(
        title: const Text("My Job History"),
        backgroundColor: Colors.orangeAccent,
        actions: [
          IconButton(
            onPressed: isLoading
                ? null
                : () async {
                    setState(() => isLoading = true);
                    await _fetchJobs();
                  },
            icon: isLoading
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : jobs.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "Order history is not available yet on this backend version.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(12),
              itemCount: jobs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final job = jobs[index] as Map<String, dynamic>;

                final jobId = _safeStr(job['id']);
                final backendConcise = _safeStr(job['concise_title']);

                final title = backendConcise.isNotEmpty
                    ? backendConcise
                    : _safeStr(
                        job['task_title'],
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

                final notesAny = job['important_notes'];
                final notesList = _safeStrList(notesAny);
                final notesText = (notesAny is String) ? notesAny.trim() : '';

                final actions = _safeStrList(job['actions']);
                final tags = _safeStrList(job['tags']);

                final scheduled = _fmtDate(job['scheduled_at']);
                final completed = _fmtDate(job['completed_at']);
                final paidAt = _fmtDate(job['paid_at']);

                final duration = _safeStr(job['duration_hours']);
                final people = _safeStr(job['people_required']);

                final costPence = job['estimated_cost_pence'];
                final cost = (costPence is num)
                    ? (costPence / 100).toStringAsFixed(2)
                    : '';

                return Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Theme(
                    data: Theme.of(
                      context,
                    ).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                      title: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      subtitle: Text(
                        [
                          if (created.isNotEmpty) created,
                          if (location.isNotEmpty &&
                              location != 'Unknown address')
                            location,
                        ].join(' • '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: _pill(status, rawStatus: statusRaw),
                      children: [
                        if (description.isNotEmpty) ...[
                          const Text(
                            "Requirements",
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            description,
                            style: const TextStyle(height: 1.35),
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (notesList.isNotEmpty || notesText.isNotEmpty) ...[
                          const Text(
                            "Important Notes",
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          if (notesList.isNotEmpty)
                            Wrap(
                              spacing: 8,
                              runSpacing: -6,
                              children: notesList
                                  .map(
                                    (n) => Chip(
                                      label: Text(n),
                                      backgroundColor: Colors.orange.shade50,
                                      shape: StadiumBorder(
                                        side: BorderSide(
                                          color: Colors.orange.shade200,
                                        ),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            )
                          else
                            Text(
                              notesText,
                              style: const TextStyle(height: 1.35),
                            ),
                          const SizedBox(height: 12),
                        ],
                        if (actions.isNotEmpty) ...[
                          const Text(
                            "Expected Actions",
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: actions
                                .map(
                                  (a) => Padding(
                                    padding: const EdgeInsets.only(bottom: 6),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        const Text("•  "),
                                        Expanded(
                                          child: Text(
                                            a,
                                            style: const TextStyle(
                                              height: 1.35,
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
                            runSpacing: -6,
                            children: tags
                                .map(
                                  (t) => Chip(
                                    label: Text(t),
                                    backgroundColor: Colors.orange.shade50,
                                    shape: StadiumBorder(
                                      side: BorderSide(
                                        color: Colors.orange.shade200,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(),
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
                          text: scheduled.isNotEmpty
                              ? 'Scheduled: $scheduled'
                              : '',
                        ),
                        _kvRow(
                          icon: '✅',
                          text: completed.isNotEmpty
                              ? 'Completed: $completed'
                              : '',
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
                          text: people.isNotEmpty
                              ? 'People Required: $people'
                              : '',
                        ),
                        _kvRow(
                          icon: '💰',
                          text: cost.isNotEmpty ? 'Estimated: £$cost' : '',
                        ),
                        const SizedBox(height: 14),
                        Align(
                          alignment: Alignment.centerRight,
                          child: _isCompletedStatus(statusRaw)
                              ? ElevatedButton.icon(
                                  icon: const Icon(Icons.refresh),
                                  label: const Text("Request Again"),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: () {
                                    final prefill = Map<String, dynamic>.from(
                                      job,
                                    );

                                    final anyNotes = prefill['important_notes'];
                                    if (anyNotes is String) {
                                      final chips = anyNotes
                                          .split(RegExp(r'\s*,\s*'))
                                          .map((e) => e.trim())
                                          .where((e) => e.isNotEmpty)
                                          .toList();
                                      prefill['important_notes'] = chips;
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
                                    backgroundColor: Colors.orangeAccent,
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
                                              builder: (context) =>
                                                  TrackJobScreen(
                                                    taskTitle: title,
                                                    userLocation:
                                                        location.isNotEmpty
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
                );
              },
            ),
    );
  }
}
