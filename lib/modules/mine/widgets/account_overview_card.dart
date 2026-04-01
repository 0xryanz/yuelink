import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../domain/account/account_actions.dart';
import '../../../domain/account/account_overview.dart';
import '../../../modules/yue_auth/providers/yue_auth_providers.dart';
import '../../../modules/status/status_page.dart';
import '../../../modules/store/store_page.dart';
import '../views/feedback_page.dart';
import '../../../shared/formatters/subscription_parser.dart' show formatBytes;
import '../../../theme.dart';
import '../providers/account_providers.dart';

/// 账户总览卡 + 快捷操作卡（我的页面，使用 YueLink Checkin API 数据）。
///
/// 设计：
///   - 账户总览：邮箱、套餐名、流量进度条、剩余流量、到期天数、续费按钮
///   - 快捷操作：网络状态、前往续费、加入群组、意见反馈（2×2 网格）
class AccountOverviewCard extends ConsumerWidget {
  const AccountOverviewCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overviewAsync = ref.watch(accountOverviewProvider);
    final actionsAsync = ref.watch(accountActionsProvider);

    return Column(
      children: [
        // ── 账户总览卡 ──────────────────────────────────────────────
        overviewAsync.when(
          loading: () => const _CardShell(child: _LoadingPlaceholder()),
          error: (_, __) => const _CardShell(child: _ErrorPlaceholder(isNetworkError: true)),
          data: (overview) {
            // null 表示 token 为 null（未登录）或接口失败
            if (overview == null) {
              final hasToken = ref.read(authProvider).token != null;
              return _CardShell(child: _ErrorPlaceholder(isNetworkError: hasToken));
            }
            return _CardShell(child: _OverviewContent(overview: overview));
          },
        ),
        const SizedBox(height: 12),

        // ── 快捷操作卡 ──────────────────────────────────────────────
        actionsAsync.when(
          loading: () => const _CardShell(child: _LoadingPlaceholder(height: 100)),
          error: (_, __) => _CardShell(child: _ActionsContent(actions: AccountActions.fallback)),
          data: (actions) => _CardShell(child: _ActionsContent(actions: actions)),
        ),
      ],
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

// ── 快捷操作内容 ──────────────────────────────────────────────────────────────

class _ActionsContent extends StatelessWidget {
  final AccountActions actions;
  const _ActionsContent({required this.actions});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final items = [
      _ActionItem(
        icon: Icons.monitor_heart_outlined,
        label: '网络状态',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const StatusPage()),
        ),
      ),
      _ActionItem(
        icon: Icons.shopping_bag_outlined,
        label: '前往续费',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const StorePage()),
        ),
      ),
      _ActionItem(
        icon: Icons.telegram,
        label: '加入群组',
        onTap: () => _launchTelegram(actions.telegramGroupUrl),
      ),
      _ActionItem(
        icon: Icons.feedback_outlined,
        label: '意见反馈',
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const FeedbackPage()),
        ),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '快捷操作',
          style: YLText.caption.copyWith(
            color: YLColors.zinc500,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (int i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(item: items[i], isDark: isDark),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _ActionItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ActionItem({required this.icon, required this.label, required this.onTap});
}

class _ActionButton extends StatelessWidget {
  final _ActionItem item;
  final bool isDark;
  const _ActionButton({required this.item, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: item.onTap,
      borderRadius: BorderRadius.circular(YLRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? YLColors.zinc700 : YLColors.zinc100,
          borderRadius: BorderRadius.circular(YLRadius.md),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              item.icon,
              size: 20,
              color: isDark ? YLColors.zinc300 : YLColors.zinc600,
            ),
            const SizedBox(height: 5),
            Text(
              item.label,
              style: YLText.caption.copyWith(
                color: isDark ? YLColors.zinc300 : YLColors.zinc700,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
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
  final double height;
  const _LoadingPlaceholder({this.height = 140});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
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

// ── URL 工具 ──────────────────────────────────────────────────────────────────

Future<void> _launch(String url) async {
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {}
}

Future<void> _launchTelegram(String url) async {
  // 尝试打开 Telegram App，失败则降级为浏览器
  try {
    final uri = Uri.parse(url);
    if (uri.host == 't.me') {
      final tgUri = Uri.parse(url.replaceFirst('https://t.me/', 'tg://resolve?domain='));
      if (await canLaunchUrl(tgUri)) {
        await launchUrl(tgUri);
        return;
      }
    }
  } catch (_) {}
  await _launch(url);
}
