import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:zanzo_frontend/core/services/zancrew_earnings_service.dart';

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
  Timer? _autoRefreshTimer;

  @override
  void initState() {
    super.initState();
    // First load: show fullscreen loader
    loadEarnings(showFullScreenLoader: true);

    // Auto refresh every 20 seconds while this screen is visible
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      // silent refresh – no fullscreen loader, just updates numbers/cards
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
      });
    } catch (e) {
      print("Earnings load error: $e");
      if (!mounted) return;
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final weekStart = data?["week_range_start"];
    final weekEnd = data?["week_range_end"];

    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        title: const Text(
          "Earnings",
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : (data == null || data!.isEmpty)
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "Earnings data is not available on this backend version.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          : RefreshIndicator(
              // Pull to refresh → just call loadEarnings (no fullscreen loader)
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
                    "Recent Jobs",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  ..._buildRecentJobs(),
                ],
              ),
            ),
    );
  }

  // ⬛ PREMIUM “Today” card – Big bold psychological reward
  Widget _todayEarningsCard() {
    final today = (data?["today_paise"] ?? 0) / 100;

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Today",
            style: TextStyle(color: Colors.white70, fontSize: 15),
          ),
          const SizedBox(height: 6),
          Text(
            "£${today.toStringAsFixed(2)}",
            style: const TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  // ⬛ WEEK CARD – with Thursday→Thursday cycle display
  Widget _weeklyCard(String? start, String? end) {
    final week = (data?["week_paise"] ?? 0) / 100;

    String range = "";
    try {
      if (start != null && end != null) {
        final s = DateTime.parse(start);
        final e = DateTime.parse(end);
        range =
            "${DateFormat("d MMM").format(s)} → ${DateFormat("d MMM").format(e)}";
      }
    } catch (_) {}

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(blurRadius: 16, color: Colors.black.withOpacity(0.04)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "This Week",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          if (range.isNotEmpty)
            Text(
              range,
              style: const TextStyle(fontSize: 13, color: Colors.grey),
            ),
          if (range.isNotEmpty) const SizedBox(height: 10),
          Text(
            "£${week.toStringAsFixed(2)}",
            style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  // ⬛ Pending payout card – orange highlight (NO MORE OVERFLOW)
  Widget _pendingCard() {
    final pending = (data?["pending_payout_paise"] ?? 0) / 100;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF2E6),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              "Pending (Paid on Thursday)",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            "£${pending.toStringAsFixed(2)}",
            textAlign: TextAlign.right,
            style: const TextStyle(
              fontSize: 18, // slightly smaller to avoid overflows
              fontWeight: FontWeight.w700,
              color: Colors.orange,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------
  // RECENT JOB ITEMS (Apple-style card list)
  // ---------------------------------------------------------------
  List<Widget> _buildRecentJobs() {
    final list = data?["earnings"] as List? ?? [];

    if (list.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.only(top: 20),
          child: Text("No completed jobs yet."),
        ),
      ];
    }

    return list
        .map<Widget>((item) => _jobCard(item as Map<String, dynamic>))
        .toList();
  }

  Widget _jobCard(Map<String, dynamic> item) {
    final amount = (item["crew_amount_paise"] ?? 0) / 100;
    final title = item["concise_title"] ?? "Task Completed";
    final address = item["location_address"] ?? "";
    final status = item["payout_status"] ?? "";
    final date = _formatDate(item["created_at"] as String?);

    return Container(
      padding: const EdgeInsets.all(18),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(blurRadius: 10, color: Colors.black.withOpacity(0.04)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // title
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),

          // amount
          Text(
            "£${amount.toStringAsFixed(2)}",
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),

          if (address.isNotEmpty)
            Text(
              address,
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),

          const SizedBox(height: 6),

          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                status == "paid" ? "Paid" : "Pending",
                style: TextStyle(
                  color: status == "paid" ? Colors.green : Colors.orange,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                date,
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(String? iso) {
    if (iso == null) return "";
    try {
      final dt = DateTime.parse(iso);
      return DateFormat("d MMM • h:mm a").format(dt.toLocal());
    } catch (_) {
      return iso;
    }
  }
}
