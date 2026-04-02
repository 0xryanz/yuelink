import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/account/account_overview.dart';
import '../../../modules/yue_auth/providers/yue_auth_providers.dart';
import '../../../modules/store/store_page.dart';
import '../../../shared/formatters/subscription_parser.dart' show formatBytes;
import '../../../theme.dart';
import '../providers/account_providers.dart';

/// 账户总览卡（我的页面，使用 YueLink Checkin API 数据）。
///
/// 设计：邮箱、套餐名、流量进度条、剩余流量、到期天数、续费按钮
class AccountOverviewCard extends ConsumerWidget {
  const AccountOverviewCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overviewAsync = ref.watch(accountOverviewProvider);

    return overviewAsync.when(
      loading: () => const _CardShell(child: _LoadingPlaceholder()),
      error: (_, __) => const _CardShell(child: _ErrorPlaceholder(isNetworkError: true)),
      data: (overview) {
        if (overview == null) {
          final hasToken = ref.read(authProvider).token != null;
          return _CardShell(child: _ErrorPlaceholder(isNetworkError: hasToken));
        }
        return _CardShell(child: _OverviewContent(overview: overview));
      },
    );
  }
}

// ── 账户总览内容 ──────────────────────────────────────────────────────────────

class _OverviewContent extends StatelessWidget {
  final AccountOverview overview;
  const _OverviewContent({required this.overview});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final usageRatio = overview.usageRatio;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 邮箱 + 套餐名 ────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    overview.email,
                    style: YLText.titleMedium.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDark ? YLColors.zinc700 : YLColors.zinc100,
                      borderRadius: BorderRadius.circular(YLRadius.sm),
                    ),
                    child: Text(
                      overview.planName,
                      style: YLText.caption.copyWith(
                        color: isDark ? YLColors.zinc300 : YLColors.zinc600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // ── 续费按钮 ──────────────────────────────────────────
            TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const StorePage()),
              ),
              style: TextButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
              child: const Text('续费', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // ── 流量进度条 ────────────────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '流量',
              style: YLText.caption.copyWith(color: YLColors.zinc500),
            ),
            Text(
              overview.transferTotalBytes > 0
                  ? '${formatBytes(overview.transferUsedBytes)} / ${formatBytes(overview.transferTotalBytes)}'
                  : '--',
              style: YLText.caption.copyWith(
                color: isDark ? YLColors.zinc300 : YLColors.zinc700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: usageRatio,
            minHeight: 7,
            backgroundColor: isDark ? YLColors.zinc700 : YLColors.zinc200,
            valueColor: AlwaysStoppedAnimation<Color>(_progressColor(usageRatio)),
          ),
        ),
        const SizedBox(height: 10),

        // ── 剩余流量 + 到期天数 ────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: _StatCell(
                label: '剩余流量',
                value: overview.transferTotalBytes > 0
                    ? formatBytes(overview.transferRemainingBytes)
                    : '--',
                isDark: isDark,
                align: CrossAxisAlignment.start,
              ),
            ),
            _StatCell(
              label: '套餐到期',
              value: _expiryText(overview),
              isDark: isDark,
              valueColor: _expiryColor(overview),
              align: CrossAxisAlignment.end,
            ),
          ],
        ),
      ],
    );
  }

  String _expiryText(AccountOverview o) {
    if (o.expireAt == null) return '永久';
    final d = o.daysRemaining;
    if (d == null || d < 0) return '已过期';
    if (d == 0) return '今日到期';
    return '还有 $d 天';
  }

  Color _expiryColor(AccountOverview o) {
    final d = o.daysRemaining;
    if (d == null) return YLColors.zinc500;
    if (d <= 0) return Colors.red;
    if (d <= 7) return Colors.orange;
    return YLColors.zinc500;
  }

  Color _progressColor(double ratio) {
    if (ratio < 0.6) return const Color(0xFF22C55E);
    if (ratio < 0.85) return Colors.orange;
    return Colors.red;
  }
}

class _StatCell extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;
  final Color? valueColor;
  final CrossAxisAlignment align;

  const _StatCell({
    required this.label,
    required this.value,
    required this.isDark,
    required this.align,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: align,
      children: [
        Text(label, style: YLText.caption.copyWith(color: YLColors.zinc500)),
        const SizedBox(height: 2),
        Text(
          value,
          style: YLText.label.copyWith(
            fontWeight: FontWeight.w600,
            color: valueColor ?? (isDark ? Colors.white : YLColors.zinc900),
          ),
        ),
      ],
    );
  }
}

// ── 共用外壳 / 状态占位 ────────────────────────────────────────────────────────

class _CardShell extends StatelessWidget {
  final Widget child;
  const _CardShell({required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDark ? YLColors.zinc800 : Colors.white,
        borderRadius: BorderRadius.circular(YLRadius.xl),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.08),
          width: 0.5,
        ),
        boxShadow: YLShadow.card(context),
      ),
      child: child,
    );
  }
}

class _LoadingPlaceholder extends StatelessWidget {
  const _LoadingPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 140,
      child: const Center(
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}

class _ErrorPlaceholder extends StatelessWidget {
  /// true = 网络/接口错误；false = 未登录（token 为空）
  final bool isNetworkError;
  const _ErrorPlaceholder({this.isNetworkError = true});

  @override
  Widget build(BuildContext context) {
    final msg = isNetworkError ? '数据暂时无法获取，下拉刷新重试' : '请先登录以查看账户信息';
    final icon = isNetworkError ? Icons.cloud_off_outlined : Icons.lock_outline;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 28, color: YLColors.zinc400),
          const SizedBox(height: 8),
          Text(
            msg,
            style: YLText.body.copyWith(color: YLColors.zinc500),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
