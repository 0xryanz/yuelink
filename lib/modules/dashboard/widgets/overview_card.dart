import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/startup_report.dart';
import '../../../l10n/app_strings.dart';
import '../../../providers/core_provider.dart';
import '../../../providers/profile_provider.dart';
import '../../../theme.dart';
import '../../../core/kernel/core_manager.dart';
import '../../../shared/app_notifier.dart';
import '../../settings/connection_repair_page.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Layer 2 — Overview Card (disconnect state only)
// ═══════════════════════════════════════════════════════════════════════════════

class OverviewCard extends ConsumerWidget {
  const OverviewCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final profiles = ref.watch(profilesProvider);
    final activeId = ref.watch(activeProfileIdProvider);
    final autoConnect = ref.watch(autoConnectProvider);

    String? profileName;
    String? lastUpdated;
    profiles.whenData((list) {
      final active = list.where((p) => p.id == activeId).firstOrNull;
      if (active != null) {
        profileName = active.name;
        if (active.lastUpdated != null) {
          final dt = active.lastUpdated!;
          lastUpdated = '${dt.month}/${dt.day} '
              '${dt.hour.toString().padLeft(2, '0')}:'
              '${dt.minute.toString().padLeft(2, '0')}';
        }
      }
    });

    final hasProfile = profileName != null;

    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Profile row
          Row(
            children: [
              Icon(
                hasProfile ? Icons.description_outlined : Icons.warning_amber_rounded,
                size: 14,
                color: hasProfile ? YLColors.zinc400 : YLColors.connecting,
              ),
              const SizedBox(width: 6),
              Text(
                s.navProfile,
                style: YLText.caption.copyWith(color: YLColors.zinc500),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            profileName ?? s.dashNoProfileHint,
            style: hasProfile
                ? YLText.titleMedium.copyWith(fontSize: 14)
                : YLText.body.copyWith(fontSize: 13, color: YLColors.zinc500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),

          if (lastUpdated != null) ...[
            const SizedBox(height: 2),
            Text(
              s.updatedAt(lastUpdated!),
              style: YLText.caption.copyWith(color: YLColors.zinc400),
            ),
          ],

          const SizedBox(height: 12),
          Divider(
            height: 1,
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.06),
          ),
          const SizedBox(height: 12),

          // Status pills
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _OverviewPill(
                icon: Icons.bolt_rounded,
                label: autoConnect ? s.dashAutoConnectOn : s.dashAutoConnectOff,
                isDark: isDark,
              ),
              if (hasProfile)
                _OverviewPill(
                  icon: Icons.check_circle_outline,
                  label: s.dashReadyHint.split('.').first,
                  isDark: isDark,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OverviewPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isDark;

  const _OverviewPill({
    required this.icon,
    required this.label,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(YLRadius.pill),
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.04),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: YLColors.zinc400),
          const SizedBox(width: 4),
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: YLText.caption.copyWith(
                  fontSize: 11,
                  color: isDark ? YLColors.zinc400 : YLColors.zinc600,
                )),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Startup Error Banner — shows failed step + friendly hint + repair shortcut
// ═══════════════════════════════════════════════════════════════════════════════

/// Human-readable mapping from [StartupError] codes to user-facing strings.
_ErrorInfo _resolveErrorInfo(String errorCode) {
  switch (errorCode) {
    case StartupError.soLoadFailed:
      return const _ErrorInfo(
        title: '原生库加载失败',
        hint: '安装包可能损坏，请重新安装应用',
        action: _ErrorAction.repair,
      );
    case StartupError.initCoreFailed:
      return const _ErrorInfo(
        title: '核心初始化失败',
        hint: '可尝试重启应用，或清除本地缓存后重试',
        action: _ErrorAction.repair,
      );
    case StartupError.vpnPermissionDenied:
      return const _ErrorInfo(
        title: 'VPN 权限被拒绝',
        hint: '请在「系统设置 → VPN」中授权悦通',
        action: _ErrorAction.repair,
      );
    case StartupError.vpnFdInvalid:
      return const _ErrorInfo(
        title: 'VPN 隧道创建失败',
        hint: '可尝试重建 VPN 配置，重新授权系统权限',
        action: _ErrorAction.repair,
      );
    case StartupError.configBuildFailed:
      return const _ErrorInfo(
        title: '配置解析失败',
        hint: '订阅配置可能有误，可尝试重新同步订阅',
        action: _ErrorAction.repair,
      );
    case StartupError.coreStartFailed:
      return const _ErrorInfo(
        title: '核心启动失败',
        hint: '配置内容可能存在冲突，建议查看诊断报告',
        action: _ErrorAction.report,
      );
    case StartupError.apiTimeout:
      return const _ErrorInfo(
        title: 'API 超时，核心进程可能已崩溃',
        hint: '可查看诊断报告了解详情，或尝试重建 VPN 配置',
        action: _ErrorAction.report,
      );
    case StartupError.coreDiedAfterStart:
      return const _ErrorInfo(
        title: '核心启动后崩溃',
        hint: '请查看诊断报告中的 Go Core 日志',
        action: _ErrorAction.report,
      );
    case StartupError.geoFilesFailed:
      return const _ErrorInfo(
        title: '地理规则文件异常',
        hint: '可尝试清除本地缓存后重新连接',
        action: _ErrorAction.repair,
      );
    default:
      return const _ErrorInfo(
        title: '连接失败',
        hint: '请前往修复页查看详情',
        action: _ErrorAction.repair,
      );
  }
}

enum _ErrorAction { repair, report }

class _ErrorInfo {
  final String title;
  final String hint;
  final _ErrorAction action;
  const _ErrorInfo({required this.title, required this.hint, required this.action});
}

/// Extract the error code (e.g. 'E006_CORE_START_FAILED') from failureSummary.
String? _extractErrorCode(String error) {
  final match = RegExp(r'\[([A-Z0-9_]+)\]').firstMatch(error);
  return match?.group(1);
}

class StartupErrorBanner extends StatefulWidget {
  final String error;
  const StartupErrorBanner({super.key, required this.error});

  @override
  State<StartupErrorBanner> createState() => _StartupErrorBannerState();
}

class _StartupErrorBannerState extends State<StartupErrorBanner> {
  bool _expanded = false;

  void _goToRepair() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ConnectionRepairPage()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final report = CoreManager.instance.lastReport;
    final steps = report?.steps ?? [];

    // Determine the failed step's error code for friendly messaging
    final failedStep = steps.where((s) => !s.success).firstOrNull;
    final errorCode = failedStep?.errorCode ?? _extractErrorCode(widget.error);
    final info = errorCode != null
        ? _resolveErrorInfo(errorCode)
        : const _ErrorInfo(
            title: '连接失败',
            hint: '请前往修复页查看详情',
            action: _ErrorAction.repair,
          );

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(YLRadius.md),
          border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header: friendly title + expand toggle ─────────────────────
            GestureDetector(
              onTap: steps.isNotEmpty
                  ? () => setState(() => _expanded = !_expanded)
                  : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 1),
                      child: Icon(Icons.error_outline, size: 16, color: Colors.red),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            info.title,
                            style: YLText.caption.copyWith(
                              color: Colors.red.shade700,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            info.hint,
                            style: YLText.caption.copyWith(
                              fontSize: 11,
                              color: Colors.red.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (steps.isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        size: 16,
                        color: Colors.red.shade400,
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // ── Action buttons ─────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Row(
                children: [
                  // Primary CTA: 前往修复
                  _BannerButton(
                    label: '前往修复',
                    icon: Icons.build_outlined,
                    onTap: _goToRepair,
                  ),
                  const SizedBox(width: 8),
                  // Secondary: copy report
                  _BannerButton(
                    label: '复制报告',
                    icon: Icons.copy_outlined,
                    onTap: () {
                      final text = report?.toDebugString() ?? widget.error;
                      Clipboard.setData(ClipboardData(text: text));
                      AppNotifier.info('已复制启动报告');
                    },
                  ),
                ],
              ),
            ),

            // ── Expanded step-by-step report ───────────────────────────────
            if (_expanded && steps.isNotEmpty) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final step in steps)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              step.success ? Icons.check_circle : Icons.cancel,
                              size: 14,
                              color: step.success ? Colors.green : Colors.red,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${step.name} (${step.durationMs}ms)'
                                '${step.errorCode != null ? ' [${step.errorCode}]' : ''}'
                                '${step.error != null ? '\n${step.error}' : ''}'
                                '${step.detail != null && !step.success ? '\n${step.detail}' : ''}',
                                style: YLText.caption.copyWith(
                                  fontSize: 11,
                                  color: step.success
                                      ? Colors.green.shade700
                                      : Colors.red.shade700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    // Go core logs (last few lines)
                    if (report != null && report.coreLogs.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      const Divider(height: 1),
                      const SizedBox(height: 6),
                      Text(
                        'Go Core 日志 (最后${report.coreLogs.length}行):',
                        style: YLText.caption.copyWith(
                          fontSize: 11,
                          color: Colors.red.shade600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          report.coreLogs.take(20).join('\n'),
                          style: YLText.caption.copyWith(
                            fontSize: 10,
                            fontFamily: 'monospace',
                            color: Colors.red.shade800,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Banner button ─────────────────────────────────────────────────────────────

class _BannerButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _BannerButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(YLRadius.pill),
          border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: Colors.red.shade700),
            const SizedBox(width: 4),
            Text(
              label,
              style: YLText.caption.copyWith(
                fontSize: 11,
                color: Colors.red.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
