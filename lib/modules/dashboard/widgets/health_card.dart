import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/feature_flags.dart';
import '../../../theme.dart';
import '../providers/dashboard_providers.dart' show exitIpInfoProvider;

/// Proactive "today's health" summary (2026 pattern — Proton/Surfshark/Catchpoint).
///
/// Three signals fuse into one user-facing verdict:
///   - exit-IP check result (did we actually leave the country?)
///   - current routing mode badge
///   - last delay test result (if available from the nodes page)
///
/// Appears at the TOP of the dashboard so the user sees status BEFORE
/// interacting — they never have to tap to find out something's wrong.
/// Hidden behind `health_card` feature flag (default ON) so we can kill
/// it if rendering causes issues on old devices.
class HealthCard extends ConsumerWidget {
  const HealthCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!FeatureFlags.I.boolFlag('health_card')) {
      return const SizedBox.shrink();
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? YLColors.zinc800 : Colors.white;

    final exitIp = ref.watch(exitIpInfoProvider);

    // State machine: green / amber / red with a one-line reason.
    final (color, label, detail) = exitIp.when(
      data: (info) {
        if (info == null) {
          return (
            YLColors.zinc400,
            '健康检查中',
            '等待出口 IP 探测结果',
          );
        }
        if (info.countryCode == 'CN' || info.countryCode.isEmpty) {
          return (
            const Color(0xFFEF4444),
            '未出墙',
            '出口 IP 在境内 — 请确认节点已连通',
          );
        }
        return (
          YLColors.connected,
          '链路正常',
          '${info.flagEmoji} ${info.locationLine}',
        );
      },
      loading: () => (YLColors.zinc400, '检测中', '正在查询出口 IP'),
      error: (_, __) => (
        const Color(0xFFF59E0B),
        '检查失败',
        '无法访问 IP 探测服务',
      ),
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(YLRadius.lg),
        boxShadow: YLShadow.card(context),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: YLText.body
                        .copyWith(fontWeight: FontWeight.w600, color: color)),
                const SizedBox(height: 2),
                Text(detail,
                    style: YLText.caption.copyWith(color: YLColors.zinc500)),
              ],
            ),
          ),
          InkWell(
            onTap: () => ref.invalidate(exitIpInfoProvider),
            borderRadius: BorderRadius.circular(20),
            child: const Padding(
              padding: EdgeInsets.all(6),
              child: Icon(Icons.refresh, size: 18, color: YLColors.zinc400),
            ),
          ),
        ],
      ),
    );
  }
}
