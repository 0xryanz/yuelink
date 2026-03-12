import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/core_provider.dart';
import '../../../theme.dart';

// Isolated consumer so only the two speed numbers rebuild every traffic tick
// rather than rebuilding the entire HeroCard.
class TrafficSpeedRow extends ConsumerWidget {
  const TrafficSpeedRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final traffic = ref.watch(trafficProvider);
    return Row(
      children: [
        Icon(Icons.arrow_downward_rounded, size: 13, color: YLColors.connected),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            traffic.downFormatted,
            style: YLText.mono.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 16),
        Icon(Icons.arrow_upward_rounded, size: 13, color: YLColors.accent),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            traffic.upFormatted,
            style: YLText.mono.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
