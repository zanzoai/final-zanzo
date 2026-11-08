// Shared shimmer / skeleton loading toolkit.
//
// Drop-in replacements for full-screen `Center(child: CircularProgressIndicator())`
// loaders so every screen shows a layout-shaped shimmer while it fetches data.
//
// Primitives : Shimmer, SkeletonBone, SkeletonLine, SkeletonCircle
// Composites : SkeletonList (list screens), SkeletonDetail (detail screens)
//
// lib/core/widgets/skeleton.dart

import 'package:flutter/material.dart';

// Brand-neutral bone tint — kept subtle so the sweep reads, not the blocks.
const Color _kBone = Color(0xFFE7E1D8);
const Color _kBoneHighlight = Color(0xFFF6F2EC);

// ===========================================================================
// SHIMMER ANIMATION WRAPPER
// ===========================================================================
/// Wraps [child] and sweeps a light highlight band across it on a loop.
/// Use it once around a tree of [SkeletonBone]s rather than per-bone.
class Shimmer extends StatefulWidget {
  final Widget child;
  const Shimmer({super.key, required this.child});

  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1250),
  )..repeat();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, child) {
        final v = _ctrl.value; // 0 → 1
        // Slide the gradient from off-left to off-right.
        final dx = (v * 2.0) - 1.0; // -1 → 1
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (rect) {
            return LinearGradient(
              begin: Alignment(dx - 1.0, 0),
              end: Alignment(dx + 1.0, 0),
              colors: const [
                _kBone,
                _kBoneHighlight,
                _kBone,
              ],
              stops: const [0.35, 0.5, 0.65],
            ).createShader(rect);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

// ===========================================================================
// PRIMITIVES
// ===========================================================================
/// A single rounded rectangle placeholder.
class SkeletonBone extends StatelessWidget {
  final double? width;
  final double height;
  final BorderRadius radius;

  const SkeletonBone({
    super.key,
    this.width,
    this.height = 14,
    this.radius = const BorderRadius.all(Radius.circular(8)),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(color: _kBone, borderRadius: radius),
    );
  }
}

/// A text-line placeholder. [widthFactor] (0–1) sets its fraction of the row.
class SkeletonLine extends StatelessWidget {
  final double widthFactor;
  final double height;

  const SkeletonLine({super.key, this.widthFactor = 1.0, this.height = 12});

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor.clamp(0.0, 1.0),
      child: SkeletonBone(
        height: height,
        radius: const BorderRadius.all(Radius.circular(6)),
      ),
    );
  }
}

/// A circular placeholder (avatars, icons).
class SkeletonCircle extends StatelessWidget {
  final double size;
  const SkeletonCircle({super.key, this.size = 44});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: _kBone, shape: BoxShape.circle),
    );
  }
}

/// A bordered, transparent-filled card matching the app's card surfaces.
/// Transparent fill so the shimmer tints only the bones inside it.
class SkeletonCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final double radius;

  const SkeletonCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 18,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0x11000000)),
      ),
      child: child,
    );
  }
}

// ===========================================================================
// COMPOSITE — LIST SKELETON
// ===========================================================================
/// Full-page shimmer for list-style screens (job history, refunds, dashboard,
/// chat, etc.). Renders [rows] placeholder cards.
class SkeletonList extends StatelessWidget {
  final int rows;
  final EdgeInsets padding;
  final bool showAvatar;

  const SkeletonList({
    super.key,
    this.rows = 6,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 16),
    this.showAvatar = true,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView.separated(
        padding: padding,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: rows,
        separatorBuilder: (_, __) => const SizedBox(height: 14),
        itemBuilder: (_, __) => _card(showAvatar),
      ),
    );
  }

  static Widget _card(bool showAvatar) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        // Transparent fill so the shimmer (srcATop) tints only the bones,
        // revealing the content-shaped skeleton rather than a solid block.
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x11000000)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showAvatar) ...[
            const SkeletonCircle(size: 44),
            const SizedBox(width: 14),
          ],
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLine(widthFactor: 0.55, height: 14),
                SizedBox(height: 10),
                SkeletonLine(widthFactor: 0.85, height: 11),
                SizedBox(height: 8),
                SkeletonLine(widthFactor: 0.4, height: 11),
              ],
            ),
          ),
          const SizedBox(width: 12),
          const SkeletonBone(width: 54, height: 22),
        ],
      ),
    );
  }
}

// ===========================================================================
// COMPOSITE — JOB-CARD LIST SKELETON
// ===========================================================================
/// Mirrors the job/order card used by Job History and Cancelled & Refunds:
/// title + amount on top, a status pill + date row, then an address line.
class SkeletonJobList extends StatelessWidget {
  final int rows;
  final EdgeInsets padding;

  const SkeletonJobList({
    super.key,
    this.rows = 6,
    this.padding = const EdgeInsets.all(12),
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView.separated(
        padding: padding,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: rows,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, __) => const SkeletonCard(
          radius: 16,
          padding: EdgeInsets.fromLTRB(14, 14, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: SkeletonLine(widthFactor: 0.7, height: 15)),
                  SizedBox(width: 10),
                  SkeletonBone(width: 48, height: 16),
                ],
              ),
              SizedBox(height: 12),
              Row(
                children: [
                  SkeletonBone(
                    width: 72,
                    height: 20,
                    radius: BorderRadius.all(Radius.circular(12)),
                  ),
                  SizedBox(width: 10),
                  SkeletonBone(width: 90, height: 11),
                ],
              ),
              SizedBox(height: 10),
              SkeletonLine(widthFactor: 0.85, height: 11),
            ],
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// COMPOSITE — OFFER-CARD LIST SKELETON (ZanCrew dashboard)
// ===========================================================================
/// Mirrors the dashboard offer card: bucket chip + status pill + chevron on
/// top, a large price, then when / distance rows.
class SkeletonOfferList extends StatelessWidget {
  final int rows;
  final EdgeInsets padding;

  const SkeletonOfferList({
    super.key,
    this.rows = 5,
    this.padding = const EdgeInsets.fromLTRB(0, 4, 0, 16),
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView.separated(
        padding: padding,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: rows,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, __) => const SkeletonCard(
          radius: 16,
          padding: EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SkeletonBone(
                    width: 74,
                    height: 28,
                    radius: BorderRadius.all(Radius.circular(10)),
                  ),
                  Spacer(),
                  SkeletonBone(
                    width: 68,
                    height: 28,
                    radius: BorderRadius.all(Radius.circular(999)),
                  ),
                  SizedBox(width: 6),
                  SkeletonBone(width: 18, height: 18),
                ],
              ),
              SizedBox(height: 12),
              SkeletonBone(width: 96, height: 26),
              SizedBox(height: 14),
              Row(
                children: [
                  SkeletonBone(width: 16, height: 16),
                  SizedBox(width: 8),
                  Expanded(child: SkeletonLine(widthFactor: 0.55, height: 12)),
                ],
              ),
              SizedBox(height: 9),
              Row(
                children: [
                  SkeletonBone(width: 16, height: 16),
                  SizedBox(width: 8),
                  Expanded(child: SkeletonLine(widthFactor: 0.4, height: 12)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// COMPOSITE — CHAT SKELETON
// ===========================================================================
/// Mirrors a chat thread: alternating left/right message bubbles of varied
/// widths.
class SkeletonChat extends StatelessWidget {
  final int rows;
  const SkeletonChat({super.key, this.rows = 8});

  // Deterministic bubble pattern (right = mine): width fraction + side.
  static const List<({double w, bool mine})> _pattern = [
    (w: 0.55, mine: false),
    (w: 0.4, mine: true),
    (w: 0.7, mine: false),
    (w: 0.5, mine: true),
    (w: 0.45, mine: false),
    (w: 0.62, mine: true),
    (w: 0.5, mine: false),
    (w: 0.38, mine: true),
  ];

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView.builder(
        padding: const EdgeInsets.all(14),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: rows,
        itemBuilder: (_, i) {
          final p = _pattern[i % _pattern.length];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Align(
              alignment: p.mine
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: p.w,
                alignment: p.mine
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: const SkeletonBone(
                  height: 44,
                  radius: BorderRadius.all(Radius.circular(16)),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ===========================================================================
// COMPOSITE — DETAIL SKELETON
// ===========================================================================
/// Full-page shimmer for detail-style screens (job/offer/earnings details).
/// A hero header, a body card of lines, and a bottom action bar.
class SkeletonDetail extends StatelessWidget {
  final EdgeInsets padding;
  final bool showButton;

  const SkeletonDetail({
    super.key,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 16),
    this.showButton = true,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero header block
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0x11000000)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SkeletonCircle(size: 48),
                      SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SkeletonLine(widthFactor: 0.6, height: 16),
                            SizedBox(height: 10),
                            SkeletonLine(widthFactor: 0.35, height: 12),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 18),
                  SkeletonLine(widthFactor: 1.0, height: 12),
                  SizedBox(height: 10),
                  SkeletonLine(widthFactor: 0.9, height: 12),
                  SizedBox(height: 10),
                  SkeletonLine(widthFactor: 0.5, height: 12),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Secondary info card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0x11000000)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SkeletonLine(widthFactor: 0.4, height: 13),
                  SizedBox(height: 14),
                  SkeletonLine(widthFactor: 1.0, height: 11),
                  SizedBox(height: 10),
                  SkeletonLine(widthFactor: 0.8, height: 11),
                  SizedBox(height: 10),
                  SkeletonLine(widthFactor: 0.65, height: 11),
                ],
              ),
            ),
            if (showButton) ...[
              const SizedBox(height: 28),
              const SkeletonBone(
                width: double.infinity,
                height: 52,
                radius: BorderRadius.all(Radius.circular(14)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
