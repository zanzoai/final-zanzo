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
        return 'Payment Pending';
      case 'searching':
      case 'finding_agent':
        return 'Finding Agent';
      case 'assigned':
        return 'Agent Assigned';
      case 'travelling':
      case 'traveling':
      case 'en_route':
        return 'On the Way';
      case 'arrived':
        return 'Arrived';
      case 'in_progress':
      case 'started':
        return 'In Progress';
      case 'completed':
      case 'settled':
        return 'Completed';
      case 'paid':
        return 'Paid';
      case 'cancelled':
      case 'canceled':
        return 'Cancelled';
      default:
        return raw.isEmpty ? 'Unknown' : raw;
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
      return (bg: const Color(0xFFFFF3E9), border: _warning, text: _accent);
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
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: _ink,
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 82,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: _muted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 13.5,
                color: _ink,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _paymentStatusLabel(String raw) {
    switch (raw.toLowerCase()) {
      case 'captured':
      case 'success':
      case 'succeeded':
        return 'Paid';
      case 'refunded':
        return 'Refunded';
      case 'released':
        return 'Auth released';
      case 'authorized':
        return 'Authorised';
      case 'failed':
        return 'Payment failed';
      default:
        return '';
    }
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
          'My Orders',
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
              'No orders yet',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your completed orders will appear here.',
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
    final tags = _safeStrList(job['tags']);

    final scheduled = _fmtDate(job['scheduled_at']);
    final completed = _fmtDate(job['completed_at']);

    // Duration — format as "1 hour" / "2 hours"
    final durationHours = job['duration_hours'];
    final durationLabel = (durationHours is num && durationHours > 0)
        ? '${durationHours == durationHours.truncateToDouble() ? durationHours.toInt() : durationHours}'
              ' ${durationHours == 1 ? "hour" : "hours"}'
        : '';

    // People — format as "1 person" / "2 people"
    final peopleCount = job['people_required'];
    final peopleLabel = (peopleCount is num && peopleCount > 0)
        ? '${peopleCount.toInt()} ${peopleCount.toInt() == 1 ? "person" : "people"}'
        : '';

    // Amount
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
    final amountDisplay = cost.isNotEmpty ? '$symbol$cost' : '';

    // Payment status (available after backend schema update)
    final payStatusLabel =
        _paymentStatusLabel(_safeStr(job['payment_status']));

    final isActive = !_isCompletedStatus(statusRaw);
    final pillColors = _statusColors(statusRaw);

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
                tilePadding: const EdgeInsets.fromLTRB(14, 10, 10, 8),
                childrenPadding: EdgeInsets.zero,
                // ── Collapsed: title (left) + amount (right) ──────────────
                title: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: _ink,
                        ),
                      ),
                    ),
                    if (amountDisplay.isNotEmpty) ...[
                      const SizedBox(width: 10),
                      Text(
                        amountDisplay,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                        ),
                      ),
                    ],
                  ],
                ),
                // ── Subtitle: status pill + date, then address ────────────
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: pillColors.bg,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: pillColors.border),
                            ),
                            child: Text(
                              status,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: pillColors.text,
                              ),
                            ),
                          ),
                          if (created.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                created,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: _muted,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (location.isNotEmpty &&
                          location != 'Unknown address') ...[
                        const SizedBox(height: 3),
                        Text(
                          location,
                          style: const TextStyle(
                            fontSize: 12,
                            color: _muted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                // ── Expanded area ─────────────────────────────────────────
                children: [
                  const Divider(height: 1, color: _line),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Task summary
                        if (description.isNotEmpty) ...[
                          Text(
                            description,
                            style: const TextStyle(
                              fontSize: 13.5,
                              color: _ink,
                              height: 1.5,
                            ),
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 14),
                        ],
                        // Section label
                        const Text(
                          'ORDER DETAILS',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: _muted,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Detail rows
                        _detailRow('Location', location),
                        _detailRow('Ordered', created),
                        if (scheduled.isNotEmpty)
                          _detailRow('Scheduled', scheduled),
                        if (completed.isNotEmpty)
                          _detailRow('Completed', completed),
                        _detailRow('Duration', durationLabel),
                        _detailRow('People', peopleLabel),
                        if (amountDisplay.isNotEmpty)
                          _detailRow('Amount', amountDisplay),
                        if (payStatusLabel.isNotEmpty)
                          _detailRow('Payment', payStatusLabel),
                        // Tags — subtle chips, no heading
                        if (tags.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: tags.map(_warmChip).toList(),
                          ),
                        ],
                        // Action button — full width
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 46,
                          child: _isCompletedStatus(statusRaw)
                              ? FilledButton.icon(
                                  icon: const Icon(
                                    Icons.replay_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('Order again'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: _success,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: () {
                                    final prefill =
                                        Map<String, dynamic>.from(job);
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
                              : FilledButton.icon(
                                  icon: const Icon(
                                    Icons.map_outlined,
                                    size: 18,
                                  ),
                                  label: const Text('Track this job'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: _accent,
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
                ],
              ),
            ),
            // Quick track row — visible on collapsed card for active jobs
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
                          'Track this job',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _accent,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 12,
                          color: _muted,
                        ),
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
