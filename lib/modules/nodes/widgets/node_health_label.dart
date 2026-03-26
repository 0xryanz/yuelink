import 'package:flutter/material.dart';

import '../../../theme.dart';

// ── Tag enum ─────────────────────────────────────────────────────────────────

/// Health / context label for a single proxy node.
///
/// Priority when computing (see [computeNodeHealthTag]):
///   tested delay  → stable / moderate / highLatency
///   untested      → recentlyUsed > favorite > (null)
enum NodeHealthTag { stable, moderate, highLatency, recentlyUsed, favorite }

// ── Compute helper ────────────────────────────────────────────────────────────

/// Returns the most informative [NodeHealthTag] for a node, or null if none.
///
/// Rules:
/// - delay tested (> 0):  ≤150 → stable, ≤300 → moderate, >300 → highLatency
/// - delay null/timeout:  isRecent → recentlyUsed, isFavorite → favorite
NodeHealthTag? computeNodeHealthTag({
  required int? delay,
  required bool isFavorite,
  required bool isRecent,
}) {
  if (delay != null && delay > 0) {
    if (delay <= 150) return NodeHealthTag.stable;
    if (delay <= 300) return NodeHealthTag.moderate;
    return NodeHealthTag.highLatency;
  }
  // Delay not tested or unreachable — fall back to user-context labels.
  if (isRecent) return NodeHealthTag.recentlyUsed;
  if (isFavorite) return NodeHealthTag.favorite;
  return null;
}

// ── Widget ────────────────────────────────────────────────────────────────────

/// A compact colored pill chip showing a node's health or context label.
///
/// Matches the visual style of the existing [_NodeTypeBadge] / [_Badge] chips
/// in the nodes module (same padding, radius, font size).
class NodeHealthLabel extends StatelessWidget {
  const NodeHealthLabel({
    super.key,
    required this.tag,
    required this.isDark,
  });

  final NodeHealthTag tag;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final (label, color) = _labelAndColor(tag);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(YLRadius.sm),
      ),
      child: Text(
        label,
        style: YLText.caption.copyWith(
          fontSize: 9,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  static (String, Color) _labelAndColor(NodeHealthTag tag) {
    switch (tag) {
      case NodeHealthTag.stable:
        return ('稳定', YLColors.connected);
      case NodeHealthTag.moderate:
        return ('波动', const Color(0xFFF59E0B)); // amber
      case NodeHealthTag.highLatency:
        return ('高延迟', const Color(0xFFEF4444)); // red
      case NodeHealthTag.recentlyUsed:
        return ('最近', const Color(0xFF3B82F6)); // blue
      case NodeHealthTag.favorite:
        return ('收藏', const Color(0xFFF59E0B)); // amber
    }
  }
}
