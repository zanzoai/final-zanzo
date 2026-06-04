import 'package:flutter/material.dart';

/// Clean payment chip for ONLINE-ONLY flow.
class PaymentChip extends StatelessWidget {
  final String? paymentStatus; // "paid" | anything else
  final bool compact;

  const PaymentChip({super.key, this.paymentStatus, this.compact = true});

  /// Build directly from a job/offer map.
  factory PaymentChip.fromMap(Map<String, dynamic>? m, {bool compact = true}) {
    final status = (m?['payment_status'] ?? '').toString().toLowerCase();

    return PaymentChip(
      paymentStatus: status.isEmpty ? null : status,
      compact: compact,
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = paymentStatus?.toLowerCase() ?? "";

    if (s != "paid") {
      // Only show CHIPS for successful online payments
      return const SizedBox.shrink();
    }

    // Paid chip
    return Chip(
      backgroundColor: Colors.green[50],
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      padding: compact
          ? const EdgeInsets.symmetric(horizontal: 10, vertical: 2)
          : const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      label: Text(
        "Paid",
        style: TextStyle(
          fontSize: compact ? 12 : 13.5,
          fontWeight: FontWeight.w600,
          color: Colors.green[800],
        ),
      ),
    );
  }
}
