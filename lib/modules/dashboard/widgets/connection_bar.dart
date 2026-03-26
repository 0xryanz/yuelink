import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_strings.dart';
import '../../../modules/yue_auth/providers/yue_auth_providers.dart';
import '../../../providers/connectivity_provider.dart';
import '../../../providers/core_provider.dart';
import '../../../theme.dart';

/// 顶部连接状态栏 — 品牌标识 + 用户问候 + 连接状态 Pill + 离线提示
class ConnectionBar extends ConsumerWidget {
  const ConnectionBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = ref.watch(coreStatusProvider);
    final isRunning = status == CoreStatus.running;
    final isTransitioning =
        status == CoreStatus.starting || status == CoreStatus.stopping;
    final isOffline =
        ref.watch(connectivityProvider) == ConnectivityStatus.offline;
    final email = ref.watch(userProfileProvider.select((p) => p?.email));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Brand mark
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isDark ? YLColors.zinc700 : YLColors.zinc100,
                borderRadius: BorderRadius.circular(YLRadius.md),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.06),
                  width: 0.5,
                ),
              ),
              child: Icon(
                Icons.link_rounded,
                size: 16,
                color: isDark ? Colors.white70 : YLColors.zinc700,
              ),
            ),
            const SizedBox(width: 10),
            // Greeting
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    email != null ? s.dashGreetingReturning : s.dashGreeting,
                    style: YLText.titleMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isDark ? Colors.white : YLColors.zinc900,
                    ),
                  ),
                  if (email != null)
                    Text(
                      email,
                      style: YLText.caption.copyWith(color: YLColors.zinc400),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Connection status pill
            _StatusPill(
              isRunning: isRunning,
              isTransitioning: isTransitioning,
              isDark: isDark,
              s: s,
            ),
          ],
        ),

        // Offline warning (inline, compact)
        if (isOffline) ...[
          const SizedBox(height: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.orange.withValues(alpha: 0.15)
                  : Colors.orange.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(YLRadius.md),
              border: Border.all(
                color: Colors.orange.withValues(alpha: 0.30),
                width: 0.5,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.wifi_off_rounded,
                  size: 14,
                  color: isDark ? Colors.orange[300] : Colors.orange[800],
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    s.noNetworkConnection,
                    style: YLText.caption.copyWith(
                      color:
                          isDark ? Colors.orange[300] : Colors.orange[800],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  final bool isRunning;
  final bool isTransitioning;
  final bool isDark;
  final S s;

  const _StatusPill({
    required this.isRunning,
    required this.isTransitioning,
    required this.isDark,
    required this.s,
  });

  @override
  Widget build(BuildContext context) {
    final Color dotColor = isRunning
        ? YLColors.connected
        : (isTransitioning ? YLColors.connecting : YLColors.zinc400);
    final String label = isRunning
        ? s.statusConnected
        : (isTransitioning ? s.statusProcessing : s.statusDisconnected);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isRunning
            ? YLColors.connected.withValues(alpha: isDark ? 0.15 : 0.08)
            : (isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.04)),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isRunning
              ? YLColors.connected.withValues(alpha: 0.25)
              : Colors.transparent,
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: dotColor,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: YLText.caption.copyWith(
              color: isRunning
                  ? YLColors.connected
                  : (isDark ? YLColors.zinc400 : YLColors.zinc500),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
