import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../i18n/app_strings.dart';
import '../../../theme.dart';
import '../providers/connections_providers.dart';
import 'stat_item.dart';

class SummaryBar extends ConsumerWidget {
  final int downloadTotal;
  final int uploadTotal;
  const SummaryBar({super.key, required this.downloadTotal, required this.uploadTotal});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // The connection count is its own thin provider so the count digit
    // and the totals can rebuild independently of each other.
    final count = ref.watch(connectionCountProvider);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: isDark ? YLColors.zinc900 : Colors.white,
        borderRadius: BorderRadius.circular(YLRadius.xl),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha:0.08) : Colors.black.withValues(alpha:0.05),
          width: 0.5,
        ),
        boxShadow: YLShadow.card(context),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          StatItem(
            icon: Icons.cable_rounded,
            label: s.statConnections,
            value: '$count',
            color: isDark ? Colors.white : YLColors.primary,
          ),
          Container(width: 1, height: 32, color: isDark ? Colors.white.withValues(alpha:0.1) : Colors.black.withValues(alpha:0.05)),
          StatItem(
            icon: Icons.arrow_downward_rounded,
            label: s.statTotalDownload,
            value: _formatBytes(downloadTotal),
            color: YLColors.connected,
          ),
          Container(width: 1, height: 32, color: isDark ? Colors.white.withValues(alpha:0.1) : Colors.black.withValues(alpha:0.05)),
          StatItem(
            icon: Icons.arrow_upward_rounded,
            label: s.statTotalUpload,
            value: _formatBytes(uploadTotal),
            color: Colors.blue.shade500,
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)}KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }
}
