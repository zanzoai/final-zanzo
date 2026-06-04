// Skeleton (loading) UI components using shimmer effect.
// Includes: TaskSkeleton, PriceSkeleton, ButtonSkeleton.
//
// lib/features/user/widgets/skeletons.dart

import 'package:flutter/material.dart';

// ===========================================================================
// SHIMMER ANIMATION WRAPPER
// ===========================================================================
class _Shimmer extends StatefulWidget {
  final Widget child;
  const _Shimmer({required this.child});

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  late final Animation<double> _anim =
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        final v = _anim.value; // 0 → 1 shimmer progress

        final left = (v - 0.20).clamp(0.0, 1.0);
        final mid = v.clamp(0.0, 1.0);
        final right = (v + 0.20).clamp(0.0, 1.0);

        return ShaderMask(
          shaderCallback: (rect) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                Colors.white.withOpacity(0.15),
                Colors.white.withOpacity(0.45),
                Colors.white.withOpacity(0.15),
              ],
              stops: [left, mid, right],
            ).createShader(rect);
          },
          blendMode: BlendMode.srcATop,
          child: widget.child,
        );
      },
    );
  }
}

// ===========================================================================
// BONE (BASE SHAPE)
// ===========================================================================
class _Bone extends StatelessWidget {
  final double height;
  final double width;
  final BorderRadius radius;

  const _Bone({
    required this.height,
    required this.width,
    this.radius = const BorderRadius.all(Radius.circular(10)),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: radius,
      ),
    );
  }
}

// ===========================================================================
// TASK SKELETON (FULL CARD)
// ===========================================================================
class TaskSkeleton extends StatelessWidget {
  const TaskSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return _Shimmer(
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: Colors.grey.shade200),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            // Header bar
            Container(
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: const Row(
                children: [
                  _Bone(
                    height: 24,
                    width: 24,
                    radius: BorderRadius.all(Radius.circular(6)),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: _Bone(height: 16, width: double.infinity),
                  ),
                ],
              ),
            ),

            // Body content skeleton
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _Bone(height: 18, width: 220),
                  SizedBox(height: 12),
                  _Bone(height: 12, width: 260),
                  SizedBox(height: 8),
                  _Bone(height: 12, width: 180),
                  SizedBox(height: 16),
                  _Bone(height: 12, width: double.infinity),
                  SizedBox(height: 8),
                  _Bone(height: 12, width: double.infinity),
                  SizedBox(height: 8),
                  _Bone(height: 12, width: 200),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ===========================================================================
// PRICE SKELETON
// ===========================================================================
class PriceSkeleton extends StatelessWidget {
  const PriceSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const _Shimmer(
      child: Row(
        children: [
          Icon(Icons.monetization_on, color: Colors.green),
          SizedBox(width: 8),
          _Bone(height: 18, width: 90),
        ],
      ),
    );
  }
}

// ===========================================================================
// BUTTON SKELETON
// ===========================================================================
class ButtonSkeleton extends StatelessWidget {
  const ButtonSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return _Shimmer(
      child: Container(
        width: double.infinity,
        height: 52,
        decoration: BoxDecoration(
          color: Colors.orange.shade200,
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }
}