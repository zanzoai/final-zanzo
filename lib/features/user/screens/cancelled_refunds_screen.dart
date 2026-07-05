// lib/features/user/screens/cancelled_refunds_screen.dart

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:zanzo_frontend/core/services/api_service.dart';

const _kBg = Color(0xFFFCFAF6);
const _kInk = Color(0xFF26211C);
const _kMuted = Color(0xFF8C8378);
const _kLine = Color(0xFFE8E2D9);
const _kAccent = Color(0xFFD97706);

class CancelledRefundsScreen extends StatefulWidget {
  const CancelledRefundsScreen({super.key});

  static const routeName = '/cancelled_refunds';

  @override
  State<CancelledRefundsScreen> createState() => _CancelledRefundsScreenState();
}

class _CancelledRefundsScreenState extends State<CancelledRefundsScreen> {
  List<Map<String, dynamic>> _jobs = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.getJson('/tasks/my');
      if (res.statusCode == 200) {
        final decoded = jsonDecode(res.body);
        if (decoded is List) {
          setState(() {
            _jobs = decoded.whereType<Map<String, dynamic>>().where((j) {
              final status = (j['status'] as String? ?? '').toLowerCase();
              final payStatus = (j['payment_status'] as String? ?? '')
                  .toLowerCase();
              return status == 'cancelled' || payStatus == 'refunded';
            }).toList();
          });
        }
      }
    } catch (_) {
      // network error — leave list empty
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _title(Map<String, dynamic> j) =>
      (j['short_title'] ?? j['title'] ?? 'Unnamed job').toString();

  String _amount(Map<String, dynamic> j) {
    final amount = j['estimated_amount'];
    if (amount == null) return '';
    final currency = (j['currency'] as String? ?? 'GBP').toUpperCase();
    final symbol = currency == 'GBP'
        ? '£'
        : currency == 'INR'
        ? '₹'
        : currency;
    final n = amount as num;
    final formatted = n == n.truncateToDouble()
        ? n.toStringAsFixed(0)
        : n.toStringAsFixed(2);
    return '$symbol$formatted';
  }

  String _date(Map<String, dynamic> j) {
    final raw = j['created_at'] as String?;
    if (raw == null) return '';
    try {
      return DateFormat('d MMM yyyy').format(DateTime.parse(raw).toLocal());
    } catch (_) {
      return raw;
    }
  }

  ({String label, Color bg, Color border, Color text}) _statusStyle(
    Map<String, dynamic> j,
  ) {
    final status = (j['status'] as String? ?? '').toLowerCase();
    final payStatus = (j['payment_status'] as String? ?? '').toLowerCase();

    if (payStatus == 'refunded') {
      return (
        label: 'Refunded',
        bg: const Color(0xFFE3F2FD),
        border: const Color(0xFF64B5F6),
        text: const Color(0xFF1565C0),
      );
    }
    if (status == 'cancelled' || status == 'canceled') {
      return (
        label: 'Cancelled',
        bg: const Color(0xFFFFEBEE),
        border: const Color(0xFFE57373),
        text: const Color(0xFFC62828),
      );
    }
    return (
      label: status,
      bg: const Color(0xFFF5F5F5),
      border: const Color(0xFFBDBDBD),
      text: const Color(0xFF616161),
    );
  }

  String _paymentLabel(String? ps) {
    switch ((ps ?? '').toLowerCase()) {
      case 'cancelled':
      case 'released':
        return 'Authorisation released — you were not charged';
      case 'refunded':
        return 'Refunded to your original payment method';
      case 'failed':
        return 'Payment was not collected';
      case 'captured':
      case 'success':
      case 'succeeded':
        return 'Payment collected';
      default:
        return '';
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        title: const Text(
          'Cancelled & Refunds',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: _kBg,
        foregroundColor: _kInk,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        actions: [
          if (!_loading)
            IconButton(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'Refresh',
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _kAccent))
          : _jobs.isEmpty
          ? _emptyState()
          : RefreshIndicator(
              color: _kAccent,
              onRefresh: _load,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                itemCount: _jobs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) => _jobCard(_jobs[i]),
              ),
            ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 52,
              color: _kMuted.withValues(alpha: 0.45),
            ),
            const SizedBox(height: 16),
            const Text(
              'No cancelled or refunded orders yet.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _kMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _jobCard(Map<String, dynamic> j) {
    final s = _statusStyle(j);
    final amountStr = _amount(j);
    final payLabel = _paymentLabel(j['payment_status'] as String?);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kLine),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  _title(j),
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: _kInk,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: s.bg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: s.border),
                ),
                child: Text(
                  s.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: s.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (amountStr.isNotEmpty) ...[
                Text(
                  amountStr,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: _kInk,
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Text(
                _date(j),
                style: const TextStyle(fontSize: 13, color: _kMuted),
              ),
            ],
          ),
          if (payLabel.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              payLabel,
              style: const TextStyle(fontSize: 13, color: _kMuted, height: 1.4),
            ),
          ],
        ],
      ),
    );
  }
}
