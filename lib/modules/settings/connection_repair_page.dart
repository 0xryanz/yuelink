import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/kernel/core_manager.dart';
import '../../core/platform/vpn_service.dart';
import '../../l10n/app_strings.dart';
import '../../shared/app_notifier.dart';
import '../../theme.dart';
import '../yue_auth/providers/yue_auth_providers.dart';
import 'startup_report_page.dart';

/// Connection repair tools: rebuild VPN, clear config, re-sync subscription,
/// view diagnostics.
class ConnectionRepairPage extends ConsumerStatefulWidget {
  const ConnectionRepairPage({super.key});

  @override
  ConsumerState<ConnectionRepairPage> createState() =>
      _ConnectionRepairPageState();
}

class _ConnectionRepairPageState extends ConsumerState<ConnectionRepairPage> {
  bool _busy = false;

  Future<void> _run(String label, Future<bool> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // Stop core first to avoid conflicts
      if (CoreManager.instance.isRunning) {
        await CoreManager.instance.stop();
      }
      final ok = await action();
      if (mounted) {
        if (ok) {
          AppNotifier.success('$label 完成');
        } else {
          AppNotifier.error('$label 失败');
        }
      }
    } catch (e) {
      if (mounted) AppNotifier.error('$label 失败: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final divColor = isDark
        ? Colors.white.withValues(alpha: 0.06)
        : Colors.black.withValues(alpha: 0.06);

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('连接修复'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Status ──
          _Card(isDark: isDark, children: [
            _StatusRow(isDark: isDark),
          ]),
          const SizedBox(height: 20),

          // ── Repair actions ──
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text('修复工具',
                style: YLText.caption.copyWith(
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                    color: YLColors.zinc400)),
          ),
          _Card(isDark: isDark, children: [
            _ActionRow(
              icon: Icons.vpn_key_outlined,
              label: '重建 VPN 配置',
              subtitle: '删除旧 VPN 隧道，下次连接时重新创建并弹出系统授权',
              isDark: isDark,
              busy: _busy,
              onTap: () => _run('重建 VPN', () async {
                final ok = await VpnService.resetVpnProfile();
                return ok;
              }),
            ),
            Divider(height: 1, color: divColor),
            _ActionRow(
              icon: Icons.delete_sweep_outlined,
              label: '清除隧道配置',
              subtitle: '删除 App Group 中的 config.yaml 和 GEO 数据，强制重新生成',
              isDark: isDark,
              busy: _busy,
              onTap: () => _run('清除配置', () async {
                final ok = await VpnService.clearAppGroupConfig();
                return ok;
              }),
            ),
            Divider(height: 1, color: divColor),
            _ActionRow(
              icon: Icons.sync_outlined,
              label: '重新同步订阅',
              subtitle: '重新从服务端拉取订阅配置并解析',
              isDark: isDark,
              busy: _busy,
              onTap: () => _run('同步订阅', () async {
                final token = ref.read(authProvider).token;
                if (token == null) {
                  AppNotifier.error('请先登录');
                  return false;
                }
                final api = ref.read(xboardApiProvider);
                await api.getSubscribeData(token);
                return true;
              }),
            ),
            Divider(height: 1, color: divColor),
            _ActionRow(
              icon: Icons.cleaning_services_outlined,
              label: '清除本地缓存',
              subtitle: '删除本地配置文件、日志、启动报告',
              isDark: isDark,
              busy: _busy,
              onTap: () => _run('清除缓存', () async {
                final appDir = await getApplicationSupportDirectory();
                final targets = [
                  'config.yaml',
                  'startup_report.json',
                  'settings.json',
                ];
                for (final name in targets) {
                  final f = File('${appDir.path}/$name');
                  if (f.existsSync()) f.deleteSync();
                }
                return true;
              }),
            ),
          ]),
          const SizedBox(height: 20),

          // ── Diagnostics ──
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text('诊断',
                style: YLText.caption.copyWith(
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                    color: YLColors.zinc400)),
          ),
          _Card(isDark: isDark, children: [
            _ActionRow(
              icon: Icons.bug_report_outlined,
              label: s.diagnostics,
              subtitle: '查看最近一次连接的启动步骤和耗时',
              isDark: isDark,
              busy: false,
              trailing: const Icon(Icons.chevron_right,
                  size: 18, color: YLColors.zinc400),
              onTap: () => Navigator.push(context,
                  MaterialPageRoute(builder: (_) => const StartupReportPage())),
            ),
          ]),
          const SizedBox(height: 32),

          // ── One-click full repair ──
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy
                  ? null
                  : () => _run('一键修复', () async {
                        // Full sequence: stop → reset VPN → clear config → done
                        await VpnService.resetVpnProfile();
                        await VpnService.clearAppGroupConfig();
                        return true;
                      }),
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.auto_fix_high_rounded, size: 18),
              label: Text(_busy ? '修复中...' : '一键修复全部'),
              style: FilledButton.styleFrom(
                backgroundColor: isDark ? YLColors.zinc700 : YLColors.zinc800,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(YLRadius.lg)),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '一键修复将停止 VPN → 删除旧隧道 → 清除配置缓存\n修复后重新点击连接即可',
            style: YLText.caption.copyWith(color: YLColors.zinc400),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Helper widgets ──────────────────────────────────────────────────────────

class _StatusRow extends StatelessWidget {
  final bool isDark;
  const _StatusRow({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final running = CoreManager.instance.isRunning;
    final report = CoreManager.instance.lastReport;
    final lastResult = report?.overallSuccess;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(
            running
                ? Icons.check_circle_rounded
                : lastResult == false
                    ? Icons.error_rounded
                    : Icons.radio_button_unchecked_rounded,
            color: running
                ? YLColors.connected
                : lastResult == false
                    ? Colors.red
                    : YLColors.zinc400,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              running
                  ? '连接正常'
                  : lastResult == false
                      ? '上次连接失败: ${report?.failureSummary ?? "未知错误"}'
                      : '未连接',
              style: YLText.body.copyWith(
                  color: isDark ? YLColors.zinc200 : YLColors.zinc700),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final bool isDark;
  final List<Widget> children;
  const _Card({required this.isDark, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool isDark;
  final bool busy;
  final Widget? trailing;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.isDark,
    required this.busy,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: busy ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(icon,
                size: 20,
                color: isDark ? YLColors.zinc300 : YLColors.zinc600),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: YLText.body.copyWith(
                          fontWeight: FontWeight.w500,
                          color:
                              isDark ? YLColors.zinc200 : YLColors.zinc700)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: YLText.caption.copyWith(color: YLColors.zinc400)),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
