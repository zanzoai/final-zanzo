// lib/features/common/reviews/crew_reviews.dart
//
// Customer-facing review UI for ZanCrew members:
//   • showCrewReviewSheet   — rate + comment a crew member after task completion
//                             (POST /zancrew/tasks/{task_id}/review).
//   • showCrewProfileSheet  — crew profile with rating summary + received reviews
//                             (GET /zancrew/users/{id}/rating_summary [+ /reviews]).
//
// Both are self-contained modal bottom sheets styled from AppTheme tokens.

import 'package:flutter/material.dart';

import 'package:zanzo_frontend/core/theme/app_theme.dart';
import 'package:zanzo_frontend/core/services/zancrew_api.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

String _titleCase(String s) => s
    .trim()
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
    .join(' ');

double _asDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

int _asInt(dynamic v) {
  if (v is num) return v.round();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

/// Best-effort extraction of a reviewer display name from a ReviewOut map.
String _reviewerName(Map<String, dynamic> r) {
  for (final k in ['reviewer_name', 'author_name', 'reviewer', 'name']) {
    final v = (r[k] ?? '').toString().trim();
    if (v.isNotEmpty) return _titleCase(v);
  }
  return 'Zanzo customer';
}

String _reviewComment(Map<String, dynamic> r) {
  for (final k in ['comment', 'text', 'body', 'message']) {
    final v = (r[k] ?? '').toString().trim();
    if (v.isNotEmpty) return v;
  }
  return '';
}

// ---------------------------------------------------------------------------
// Star row (read-only)
// ---------------------------------------------------------------------------

class StarRow extends StatelessWidget {
  final double rating;
  final double size;
  const StarRow({super.key, required this.rating, this.size = 16});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        IconData icon;
        if (rating >= i + 1) {
          icon = Icons.star_rounded;
        } else if (rating >= i + 0.5) {
          icon = Icons.star_half_rounded;
        } else {
          icon = Icons.star_outline_rounded;
        }
        return Icon(icon, size: size, color: AppColors.warning);
      }),
    );
  }
}

// ===========================================================================
// 1) REVIEW SUBMISSION SHEET
// ===========================================================================

Future<bool> showCrewReviewSheet(
  BuildContext context, {
  required String taskId,
  String? crewName,
}) async {
  final submitted = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CrewReviewSheet(taskId: taskId, crewName: crewName),
  );
  return submitted ?? false;
}

class _CrewReviewSheet extends StatefulWidget {
  final String taskId;
  final String? crewName;
  const _CrewReviewSheet({required this.taskId, this.crewName});

  @override
  State<_CrewReviewSheet> createState() => _CrewReviewSheetState();
}

class _CrewReviewSheetState extends State<_CrewReviewSheet> {
  int _rating = 0;
  final TextEditingController _comment = TextEditingController();
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating < 1) {
      setState(() => _error = 'Tap a star to rate your crew.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ZanCrewApi.submitReview(
        taskId: widget.taskId,
        rating: _rating,
        comment: _comment.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _titleCase(widget.crewName ?? '');
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: viewInsets),
        child: Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                name.isEmpty
                    ? 'How was your task?'
                    : 'How was $name?',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Your rating helps keep the ZanCrew community trusted.',
                style: TextStyle(fontSize: 13.5, color: AppColors.muted),
              ),
              const SizedBox(height: 18),
              // Interactive stars.
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(5, (i) {
                  final filled = i < _rating;
                  return IconButton(
                    onPressed: _submitting
                        ? null
                        : () => setState(() {
                              _rating = i + 1;
                              _error = null;
                            }),
                    iconSize: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      filled ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: filled ? AppColors.warning : AppColors.divider,
                    ),
                  );
                }),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _comment,
                enabled: !_submitting,
                minLines: 2,
                maxLines: 4,
                maxLength: 500,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: 'Add a comment (optional)',
                  filled: true,
                  fillColor: AppColors.surfaceMuted,
                  counterText: '',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFDC2626),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.saffron,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        AppColors.saffron.withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  onPressed: _submitting ? null : _submit,
                  child: _submitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Submit review',
                          style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
              ),
              TextButton(
                onPressed:
                    _submitting ? null : () => Navigator.of(context).pop(false),
                child: const Text(
                  'Maybe later',
                  style: TextStyle(color: AppColors.muted),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ===========================================================================
// 2) CREW PROFILE + REVIEWS SHEET
// ===========================================================================

Future<void> showCrewProfileSheet(
  BuildContext context, {
  required String? crewUserId,
  String? crewName,
  String? avatarUrl,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CrewProfileSheet(
      crewUserId: crewUserId,
      crewName: crewName,
      avatarUrl: avatarUrl,
    ),
  );
}

class _CrewProfileSheet extends StatefulWidget {
  final String? crewUserId;
  final String? crewName;
  final String? avatarUrl;
  const _CrewProfileSheet({
    required this.crewUserId,
    this.crewName,
    this.avatarUrl,
  });

  @override
  State<_CrewProfileSheet> createState() => _CrewProfileSheetState();
}

class _CrewProfileSheetState extends State<_CrewProfileSheet> {
  bool _loading = true;
  double _avg = 0;
  int _count = 0;
  List<Map<String, dynamic>> _reviews = [];
  bool _reviewsUnavailable = false; // backend list endpoint not present

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.crewUserId;
    if (id == null || id.isEmpty) {
      setState(() {
        _loading = false;
        _reviewsUnavailable = true;
      });
      return;
    }

    // Summary (avg + count) — required.
    try {
      final s = await ZanCrewApi.getUserRatingSummary(id);
      _avg = _asDouble(s['avg_rating']);
      _count = _asInt(s['reviews_count']);
    } catch (_) {
      // leave zeros
    }

    // Individual reviews — optional (endpoint may not exist yet).
    try {
      _reviews = await ZanCrewApi.getUserReviews(id);
    } catch (_) {
      _reviewsUnavailable = true;
    }

    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final name = _titleCase(widget.crewName ?? '');
    final hasName = name.isNotEmpty;
    final avatar = (widget.avatarUrl ?? '').trim();

    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              // Header
              Row(
                children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: AppColors.saffron.withValues(alpha: 0.12),
                    backgroundImage:
                        avatar.isNotEmpty ? NetworkImage(avatar) : null,
                    child: avatar.isEmpty
                        ? Text(
                            hasName ? name.characters.first.toUpperCase() : 'Z',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                              color: AppColors.saffron,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hasName ? name : 'ZanCrew partner',
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Verified ZanCrew partner',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              // Rating summary card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceMuted,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: _loading
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.saffron,
                          ),
                        ),
                      )
                    : Row(
                        children: [
                          Text(
                            _count == 0 ? '—' : _avg.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                              color: AppColors.ink,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              StarRow(rating: _avg, size: 18),
                              const SizedBox(height: 4),
                              Text(
                                _count == 0
                                    ? 'No ratings yet'
                                    : '$_count ${_count == 1 ? 'review' : 'reviews'}',
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  color: AppColors.muted,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Reviews',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 10),
              if (_loading)
                const SizedBox.shrink()
              else if (_reviews.isNotEmpty)
                ..._reviews.map(_reviewTile)
              else
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    _reviewsUnavailable
                        ? (_count > 0
                            ? 'This partner has $_count ${_count == 1 ? 'review' : 'reviews'}. Individual reviews will appear here soon.'
                            : 'No reviews yet.')
                        : 'No reviews yet.',
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: AppColors.muted,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _reviewTile(Map<String, dynamic> r) {
    final rating = _asDouble(r['rating']);
    final comment = _reviewComment(r);
    final who = _reviewerName(r);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  who,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
              StarRow(rating: rating, size: 14),
            ],
          ),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              comment,
              style: const TextStyle(fontSize: 13.5, color: AppColors.ink),
            ),
          ],
        ],
      ),
    );
  }
}
