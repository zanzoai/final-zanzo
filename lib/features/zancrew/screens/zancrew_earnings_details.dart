import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:zanzo_frontend/core/services/zancrew_earnings_service.dart';
import 'package:zanzo_frontend/core/widgets/error_state.dart';
import 'package:zanzo_frontend/core/widgets/skeleton.dart';

class ZanCrewEarningsDetailsScreen extends StatefulWidget {
  final String crewUserId;

  const ZanCrewEarningsDetailsScreen({super.key, required this.crewUserId});

  @override
  State<ZanCrewEarningsDetailsScreen> createState() =>
      _ZanCrewEarningsDetailsScreenState();
}

class _ZanCrewEarningsDetailsScreenState
    extends State<ZanCrewEarningsDetailsScreen> {
  Map<String, dynamic>? data;
  bool loading = true;
  bool _error = false;
  Timer? _autoRefreshTimer;

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
    loadEarnings(showFullScreenLoader: true);

    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      loadEarnings();
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  Future<void> loadEarnings({bool showFullScreenLoader = false}) async {
    if (showFullScreenLoader) {
      setState(() {
        loading = true;
      });
    }

    try {
      final result = await ZanCrewEarningsService.getEarnings(
        widget.crewUserId,
      );

      if (!mounted) return;

      setState(() {
        data = result;
        loading = false;
        _error = false;
      });
    } catch (e) {
      debugPrint('Earnings load error: $e');
      if (!mounted) return;
      setState(() {
        loading = false;
        _error = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final weekStart = data?['week_range_start'];
    final weekEnd = data?['week_range_end'];

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        foregroundColor: _ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        title: const Text(
          'Earnings',
          style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: -0.2),
        ),
      ),
      body: loading
          ? const SkeletonDetail(showButton: false)
          : (_error && (data == null || data!.isEmpty))
          ? ErrorState(
              message: "We couldn't load your earnings. Please try again.",
              onRetry: () => loadEarnings(showFullScreenLoader: true),
            )
          : (data == null || data!.isEmpty)
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Earnings data is not available on this backend version.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _muted),
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: loadEarnings,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 30),
                children: [
                  _todayEarningsCard(),
                  const SizedBox(height: 20),
                  _weeklyCard(weekStart, weekEnd),
                  const SizedBox(height: 20),
                  _pendingCard(),
                  const SizedBox(height: 24),
                  const Text(
                    'Recent Jobs',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ..._buildRecentJobs(),
                ],
              ),
            ),
    );
  }

  Widget _todayEarningsCard() {
    final today = (data?['today_paise'] ?? 0) / 100;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFF1C1917),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Today',
            style: TextStyle(
              color: Color(0xBBFFFFFF),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '£${today.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -1.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _weeklyCard(String? start, String? end) {
    final week = (data?['week_paise'] ?? 0) / 100;

    String range = '';
    try {
      if (start != null && end != null) {
        final s = DateTime.parse(start);
        final e = DateTime.parse(end);
        range =
            '${DateFormat('d MMM').format(s)} → ${DateFormat('d MMM').format(e)}';
      }
    } catch (_) {}

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            blurRadius: 16,
            color: Colors.black.withValues(alpha: 0.04),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This Week',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
          const SizedBox(height: 4),
          if (range.isNotEmpty)
            Text(range, style: const TextStyle(fontSize: 13, color: _muted)),
          if (range.isNotEmpty) const SizedBox(height: 10),
          Text(
            '£${week.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              color: _ink,
              letterSpacing: -0.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _pendingCard() {
    final pending = (data?['pending_payout_paise'] ?? 0) / 100;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'Pending (Paid on Thursday)',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: _ink,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '£${pending.toStringAsFixed(2)}',
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: _accent,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildRecentJobs() {
    final list = data?['earnings'] as List? ?? [];

    if (list.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.only(top: 20),
          child: Text(
            'No completed jobs yet.',
            style: TextStyle(color: _muted),
          ),
        ),
      ];
    }

    return list
        .map<Widget>((item) => _jobCard(item as Map<String, dynamic>))
        .toList();
  }

  Widget _jobCard(Map<String, dynamic> item) {
    final amount = (item['crew_amount_paise'] ?? 0) / 100;
    final title = item['concise_title'] ?? 'Task Completed';
    final address = item['location_address'] ?? '';
    final status = item['payout_status'] ?? '';
    final date = _formatDate(item['created_at'] as String?);

    return Container(
      padding: const EdgeInsets.all(18),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
        boxShadow: [
          BoxShadow(
            blurRadius: 10,
            color: Colors.black.withValues(alpha: 0.04),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '£${amount.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: _ink,
            ),
          ),
          const SizedBox(height: 6),
          if (address.isNotEmpty)
            Text(address, style: const TextStyle(fontSize: 14, color: _muted)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: status == 'paid' ? const Color(0xFFECFDF5) : _surface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _border),
                ),
                child: Text(
                  status == 'paid' ? 'Paid' : 'Pending',
                  style: TextStyle(
                    color: status == 'paid' ? _success : _accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
              ),
              Text(date, style: const TextStyle(fontSize: 13, color: _muted)),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso);
      return DateFormat('d MMM • h:mm a').format(dt.toLocal());
    } catch (_) {
      return iso;
    }
  }
}
