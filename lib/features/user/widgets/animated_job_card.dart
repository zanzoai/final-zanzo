// This widget displays a job preview card with smooth expand/collapse animation.
// Shows job title, requirements, actions, and tags.

// lib/features/user/widgets/animated_job_card.dart

import 'package:flutter/material.dart';

class AnimatedJobCard extends StatefulWidget {
  final String jobTitle;
  final String requirements;
  final List<String> actions;
  final List<String> tags;

  const AnimatedJobCard({
    super.key,
    required this.jobTitle,
    required this.requirements,
    required this.actions,
    required this.tags,
  });

  @override
  State<AnimatedJobCard> createState() => _AnimatedJobCardState();
}

class _AnimatedJobCardState extends State<AnimatedJobCard> {
  bool _expanded = false;

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // -------------------------------------------------------------------
          // Title
          // -------------------------------------------------------------------
          Text(
            widget.jobTitle,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 18,
              overflow: TextOverflow.ellipsis,
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 8),

          // -------------------------------------------------------------------
          // COLLAPSED VIEW
          // -------------------------------------------------------------------
          if (!_expanded) ...[
            Text(
              widget.requirements,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(color: Colors.black87),
            ),
            const SizedBox(height: 6),

            // Show 1–2 actions preview
            if (widget.actions.isNotEmpty)
              Text(
                "• ${widget.actions.first}",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            if (widget.actions.length > 1)
              Text(
                "• ${widget.actions[1]}",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),

            const SizedBox(height: 8),

            // Tags preview
            Wrap(
              spacing: 6,
              children: widget.tags.take(2).map((t) {
                return Chip(
                  label: Text(t, style: const TextStyle(fontSize: 12)),
                  backgroundColor: Colors.grey[100],
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                );
              }).toList(),
            ),
          ],

          // -------------------------------------------------------------------
          // EXPANDED VIEW
          // -------------------------------------------------------------------
          if (_expanded) ...[
            // Requirements
            Text(
              "Your Requirements",
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.requirements,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),

            // Actions
            Text(
              "Expected Actions",
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: widget.actions
                  .map(
                    (a) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text("• $a"),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),

            // Tags list
            Wrap(
              spacing: 6,
              children: [
                ...widget.tags.map(
                  (t) => Chip(
                    label: Text(t, style: const TextStyle(fontSize: 12)),
                    backgroundColor: Colors.grey[100],
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                ),
                // Future feature: adding an action
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: const Text("Add action"),
                  onPressed: () {
                    // later expansion point
                  },
                ),
              ],
            ),
          ],

          // -------------------------------------------------------------------
          // Expand/Collapse Button
          // -------------------------------------------------------------------
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(_expanded ? "Show less" : "Tap to expand"),
            ),
          ),
        ],
      ),
    );
  }
}