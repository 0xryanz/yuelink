import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_strings.dart';
import '../../../modules/yue_auth/providers/yue_auth_providers.dart';
import '../../../providers/core_provider.dart';
import '../../../shared/formatters/subscription_parser.dart' show formatBytes;
import '../../../theme.dart';
import '../../nodes/providers/nodes_providers.dart';

// ── Health grade ──────────────────────────────────────────────────────────────

enum _Grade { excellent, fair, poor, unknown, offline }

extension _GradeX on _Grade {
  String label(S s) {
    switch (this) {
      case _Grade.excellent:
        return s.gradeExcellent;
      case _Grade.fair:
        return s.gradeFair;
      case _Grade.poor:
        return s.gradePoor;
      case _Grade.unknown:
        return s.gradeUnknown;
      case _Grade.offline:
        return s.gradeOffline;
    }
  }

  Color get dotColor {
    switch (this) {
      case _Grade.excellent:
        return YLColors.connected;
      case _Grade.fair:
        return YLColors.connecting;
      case _Grade.poor:
        return YLColors.error;
      case _Grade.unknown:
      case _Grade.offline:
        return YLColors.zinc400;
    }
  }

  /// Tint for the label text. Null → use default body text color.
  Color? get textColor {
    switch (this) {
      case _Grade.excellent:
        return YLColors.connected;
      case _Grade.poor:
        return YLColors.error;
      default:
        return null;
    }
  }
}

// ── Main widget ───────────────────────────────────────────────────────────────

/// 服务状态概览 — 3 列紧凑卡片，放置在首页套餐卡下方。
///
/// 列：到期时间 | 剩余流量 | 线路健康
///
/// 数据全部来源客户端，不依赖后台服务状态 API：
///   - 到期时间 / 流量：[userProfileProvider] (XBoard 缓存)
///   - 线路健康：[coreStatusProvider] + [delayResultsProvider] + [activeProxyInfoProvider]
///
/// 健康度评分规则：
///   - 未连接           → 离线 (灰)
///   - 连接中，未测速   → 未测 (灰)
///   - 延迟 < 150 ms    → 优 (绿)
///   - 延迟 150–400 ms  → 中 (橙)
///   - 延迟 > 400 ms 或超时 → 差 (红)
///
/// 未登录时隐藏（返回 [SizedBox.shrink]）。
class ServiceStatusBar extends ConsumerWidget {
  const ServiceStatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isLoggedIn = ref.watch(
        authProvider.select((a) => a.status == AuthStatus.loggedIn));
    if (!isLoggedIn) return const SizedBox.shrink();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final s = S.of(context);
    final profile = ref.watch(userProfileProvider);
    final status = ref.watch(coreStatusProvider);
    final activeInfo = ref.watch(activeProxyInfoProvider);
    final delays = ref.watch(delayResultsProvider);

    final grade = _computeGrade(status, activeInfo?.nodeName, delays);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? YLColors.zinc800 : Colors.white,
        borderRadius: BorderRadius.circular(YLRadius.lg),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.08),
          width: 0.5,
        ),
        boxShadow: YLShadow.card(context),
      ),
      // IntrinsicHeight ensures all three cells share the same height
      // so the vertical dividers span the full card.
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Col 1: 到期时间 ──────────────────────────────────
            Expanded(
              child: _StatCell(
                icon: Icons.calendar_today_outlined,
                value: _expiryValue(profile, s),
                label: s.statusExpiry,
                valueColor: _expiryColor(profile),
                isDark: isDark,
              ),
            ),
            _VDivider(isDark: isDark),

            // ── Col 2: 剩余流量 ──────────────────────────────────
            Expanded(
              child: _StatCell(
                icon: Icons.data_usage_rounded,
                value: _remainingValue(profile, s),
                label: s.statusTraffic,
                valueColor: _trafficColor(profile),
                isDark: isDark,
              ),
            ),
            _VDivider(isDark: isDark),

            // ── Col 3: 线路健康 ──────────────────────────────────
            Expanded(
              child: _HealthCell(grade: grade, isDark: isDark),
            ),
          ],
        ),
      ),
    );
  }

  // ── Health computation ────────────────────────────────────────────────────

  static _Grade _computeGrade(
    CoreStatus status,
    String? nodeName,
    Map<String, int> delays,
  ) {
    if (status != CoreStatus.running) return _Grade.offline;
    if (nodeName == null || nodeName.isEmpty) return _Grade.unknown;
    final delay = delays[nodeName];
    if (delay == null) return _Grade.unknown; // not yet tested
    if (delay <= 0) return _Grade.poor; // timeout / connect error
    if (delay < 150) return _Grade.excellent;
    if (delay < 400) return _Grade.fair;
    return _Grade.poor;
  }

  // ── Data formatters ───────────────────────────────────────────────────────

  static String _expiryValue(UserProfile? p, S s) {
    if (p == null) return '—';
    if (p.isExpired) return s.statusExpired;
    final d = p.expiryDate;
    if (d == null) return '—';
    // Include year when the plan expires in a different calendar year,
    // so "3/26" doesn't become ambiguous for multi-year plans.
    if (d.year != DateTime.now().year) return '${d.year}/${d.month}/${d.day}';
    return '${d.month}/${d.day}';
  }

  static Color? _expiryColor(UserProfile? p) {
    if (p == null) return null;
    if (p.isExpired) return YLColors.error;
    final days = p.daysRemaining;
    if (days != null && days <= 7) return YLColors.connecting;
    return null;
  }

  static String _remainingValue(UserProfile? p, S s) {
    if (p == null) return '—';
    if (p.transferEnable == null) return s.statusUnlimited;
    final rem = p.remaining ?? 0;
    if (rem <= 0) return s.statusExhausted;
    return formatBytes(rem);
  }

  static Color? _trafficColor(UserProfile? p) {
    if (p?.transferEnable == null) return null;
    final rem = p!.remaining ?? 0;
    if (rem <= 0) return YLColors.error;
    final pct = p.usagePercent ?? 0.0;
    if (pct > 0.9) return YLColors.connecting;
    return null;
  }
}

// ── Helper widgets ────────────────────────────────────────────────────────────

/// Generic stat cell — icon + value + label.
class _StatCell extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color? valueColor;
  final bool isDark;

  const _StatCell({
    required this.icon,
    required this.value,
    required this.label,
    this.valueColor,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final color =
        valueColor ?? (isDark ? YLColors.zinc100 : YLColors.zinc800);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: YLText.body.copyWith(
              fontWeight: FontWeight.w600,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: YLText.caption.copyWith(
              fontSize: 10,
              color: YLColors.zinc500,
            ),
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}

/// Health-grade cell — coloured dot + grade label + "线路健康" caption.
class _HealthCell extends StatelessWidget {
  final _Grade grade;
  final bool isDark;

  const _HealthCell({required this.grade, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final textColor =
        grade.textColor ?? (isDark ? YLColors.zinc100 : YLColors.zinc800);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Coloured status dot
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: grade.dotColor,
                ),
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  grade.label(S.of(context)),
                  style: YLText.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            S.of(context).statusHealth,
            style: YLText.caption.copyWith(
              fontSize: 10,
              color: YLColors.zinc500,
            ),
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}

/// Full-height hairline vertical divider between cells.
class _VDivider extends StatelessWidget {
  final bool isDark;
  const _VDivider({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 0.5,
      color: isDark
          ? Colors.white.withValues(alpha: 0.08)
          : Colors.black.withValues(alpha: 0.08),
    );
  }
}
