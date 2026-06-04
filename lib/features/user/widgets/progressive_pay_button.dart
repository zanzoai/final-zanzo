// This widget shows a progressive "Pay" button with animated states:
// idle → checking → securing → success → reset.
// Accepts: amount + currencyCode OR legacy priceText.
// Calls: onConfirmed() during the securing state.
//
// lib/features/user/widgets/progressive_pay_button.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class ProgressivePayButton extends StatefulWidget {
  /// Preferred modern API: numeric amount + currency code.
  final num? amount;
  final String? currencyCode;

  /// Legacy fallback: fully formatted price text
  /// (used only if [amount] is null).
  final String? priceText;

  /// Callback triggered during payment confirmation.
  final Future<void> Function() onConfirmed;

  /// Optional accent color for the button.
  final Color? accentColor;

  /// Label prefix (e.g., "Pay", "Pay now").
  final String labelPrefix;

  /// Optional trailing note (e.g., "/hr").
  final String? trailingNote;

  const ProgressivePayButton({
    super.key,
    required this.onConfirmed,
    this.amount,
    this.currencyCode,
    this.priceText,
    this.accentColor,
    this.labelPrefix = 'Pay ',
    this.trailingNote,
  });

  @override
  State<ProgressivePayButton> createState() => _ProgressivePayButtonState();
}

class _ProgressivePayButtonState extends State<ProgressivePayButton>
    with TickerProviderStateMixin {
  String _state = 'idle'; // idle → checking → securing → success

  late final AnimationController _progressCtrl;
  late final Animation<double> _progress;

  @override
  void initState() {
    super.initState();

    _progressCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _progress = CurvedAnimation(
      parent: _progressCtrl,
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  void dispose() {
    _progressCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // MAIN FLOW
  // ---------------------------------------------------------------------------
  Future<void> _startFlow() async {
    if (_state != 'idle') return;

    // Step 1: Checking
    setState(() => _state = 'checking');
    await Future.delayed(const Duration(milliseconds: 900));

    // Step 2: Securing
    setState(() => _state = 'securing');
    _progressCtrl.forward(from: 0);

    // Step 3: Callback executed during securing
    try {
      await widget.onConfirmed();
      setState(() => _state = 'success');

      // Short success flash
      await Future.delayed(const Duration(milliseconds: 1200));

      if (mounted) setState(() => _state = 'idle');
    } catch (_) {
      if (mounted) setState(() => _state = 'idle');
    }
  }

  // ---------------------------------------------------------------------------
  // PRICE FORMATTER
  // ---------------------------------------------------------------------------
  String _formattedPrice() {
    if (widget.amount != null && widget.currencyCode != null) {
      final format = NumberFormat.currency(
        symbol: _symbol(widget.currencyCode!),
        decimalDigits: 0,
      );
      return format.format(widget.amount);
    }
    return widget.priceText ?? '';
  }

  String _symbol(String code) {
    switch (code.toUpperCase()) {
      case 'INR':
        return '₹';
      case 'GBP':
        return '£';
      case 'USD':
        return '\$';
      default:
        return code; // fallback for EUR, SGD, etc.
    }
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final accent = widget.accentColor ?? Colors.orangeAccent;

    final label =
        '${widget.labelPrefix}${_formattedPrice()}${widget.trailingNote ?? ''}';

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: SizedBox(
        key: ValueKey(_state),
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _state == 'success'
                ? Colors.greenAccent.shade400
                : accent,
            foregroundColor: Colors.black87,
            elevation: 3,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          onPressed: _state == 'idle' ? _startFlow : null,
          child: _buildChild(label),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // STATE-BASED CONTENT
  // ---------------------------------------------------------------------------
  Widget _buildChild(String label) {
    switch (_state) {
      case 'idle':
        return Text(
          label,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        );

      case 'checking':
        return const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation(Colors.white),
              ),
            ),
            SizedBox(width: 12),
            Text(
              'Checking…',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );

      case 'securing':
        return AnimatedBuilder(
          animation: _progress,
          builder: (_, __) => Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  value: _progress.value,
                  strokeWidth: 2,
                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                ),
              ),
              const Text(
                'Securing…',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        );

      case 'success':
        return const Icon(
          Icons.check_circle_rounded,
          size: 26,
          color: Colors.white,
        );

      default:
        return const SizedBox.shrink();
    }
  }
}