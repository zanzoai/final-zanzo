// Centered error state for failed data loads — shown in the middle of a
// screen's body instead of a transient snackbar. Use it only when a load
// failed AND there is nothing to display; if content is already on screen,
// keep it and fail silently (a background refresh shouldn't wipe the view).
//
// lib/core/widgets/error_state.dart

import 'package:flutter/material.dart';

class ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;
  final IconData icon;

  const ErrorState({
    super.key,
    this.message = "We couldn't load this. Please try again.",
    this.onRetry,
    this.icon = Icons.cloud_off_rounded,
  });

  static const Color _muted = Color(0xFF8C8378);
  static const Color _accent = Color(0xFFD97706);
  static const Color _line = Color(0xFFE8E2D9);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: _muted.withValues(alpha: 0.55)),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _muted,
                height: 1.4,
              ),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Retry'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _accent,
                  side: const BorderSide(color: _line),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
