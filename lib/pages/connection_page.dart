import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../main.dart';
import '../providers/core_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/proxy_provider.dart';
import '../services/app_notifier.dart';
import '../services/core_manager.dart';
import '../services/profile_service.dart';
import '../theme.dart';

/// The main Dashboard page.
/// Redesigned with a premium "Control Center" aesthetic.
class ConnectionPage extends ConsumerWidget {
  const ConnectionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final status = ref.watch(coreStatusProvider);
    final isConnected = status == CoreStatus.running;

    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          // Premium Header
          SliverAppBar(
            expandedHeight: 100.0,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.symmetric(horizontal: YLSpacing.xl, vertical: YLSpacing.lg),
              title: Text(
                'Dashboard',
                style: YLText.display.copyWith(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 28,
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: YLSpacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Hero Status Card
                  _buildHeroCard(context, ref, status),
                  
                  const SizedBox(height: YLSpacing.xl),

                  // 2. Traffic Stats Grid
                  _buildTrafficGrid(context, ref),

                  const SizedBox(height: YLSpacing.xxl),

                  // 3. Quick Settings (Grouped List)
                  Text('SETTINGS', style: YLText.caption.copyWith(color: YLColors.zinc500, letterSpacing: 1.2)),
                  const SizedBox(height: YLSpacing.sm),
                  _buildSettingsGroup(context, ref),

                  const SizedBox(height: YLSpacing.massive),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard(BuildContext context, WidgetRef ref, CoreStatus status) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isConnected = status == CoreStatus.running;
    final isConnecting = status == CoreStatus.starting || status == CoreStatus.stopping;

    // Determine active node info
    String activeNodeName = 'Not Connected';
    String activeNodeGroup = 'Tap the switch to start';
    if (isConnected) {
      final groups = ref.watch(proxyGroupsProvider);
      if (groups.isNotEmpty) {
        try {
          final mainGroup = groups.firstWhere(
            (g) => g.name == 'PROXIES' || g.name == 'GLOBAL' || g.name == '节点选择' || g.name == 'Proxy',
            orElse: () => groups.firstWhere((g) => g.type == 'Selector', orElse: () => groups.first),
          );
          activeNodeName = mainGroup.now.isNotEmpty ? mainGroup.now : 'Direct / Auto';
          activeNodeGroup = mainGroup.name;
        } catch (_) {
          activeNodeName = 'Connected';
          activeNodeGroup = 'Active';
        }
      }
    }

    return Container(
      padding: const EdgeInsets.all(YLSpacing.xl),
      decoration: BoxDecoration(
        gradient: isConnected 
            ? LinearGradient(
                colors: [YLColors.connected.withOpacity(0.15), YLColors.connected.withOpacity(0.05)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: isConnected ? null : (isDark ? YLColors.surfaceDark : YLColors.surfaceLight),
        borderRadius: BorderRadius.circular(YLRadius.xxl),
        border: Border.all(
          color: isConnected 
              ? YLColors.connected.withOpacity(0.3) 
              : (isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.04)),
          width: 0.5,
        ),
        boxShadow: isDark ? [] : [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 20, offset: const Offset(0, 8)),
        ],
      ),
      child: Row(
        children: [
          // Left: Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    YLStatusDot(
                      color: isConnected ? YLColors.connected : (isConnecting ? YLColors.connecting : YLColors.zinc400),
                      glow: isConnected,
                    ),
                    const SizedBox(width: YLSpacing.sm),
                    Text(
                      isConnected ? 'Active' : (isConnecting ? 'Processing...' : 'Disconnected'),
                      style: YLText.label.copyWith(
                        color: isConnected ? YLColors.connected : YLColors.zinc500,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: YLSpacing.md),
                Text(
                  activeNodeName,
                  style: YLText.titleLarge.copyWith(fontSize: 22),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  activeNodeGroup,
                  style: YLText.body.copyWith(color: YLColors.zinc500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          
          // Right: Premium Power Toggle
          GestureDetector(
            onTap: isConnecting ? null : () async {
              final actions = ref.read(coreActionsProvider);
              if (isConnected) {
                await actions.stop();
              } else {
                final activeId = ref.read(activeProfileIdProvider);
                if (activeId == null) {
                  AppNotifier.warning('请先在配置页选择或添加一个订阅');
                  MainShell.switchToTab(context, MainShell.tabConfigurations);
                  return;
                }
                final config = await ProfileService.loadConfig(activeId);
                if (config == null) {
                  AppNotifier.error('无法读取配置文件');
                  return;
                }
                await actions.start(config);
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isConnected ? YLColors.connected : (isDark ? YLColors.zinc800 : YLColors.bgLight),
                boxShadow: isConnected ? [
                  BoxShadow(color: YLColors.connected.withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 4))
                ] : [],
              ),
              child: Center(
                child: isConnecting
                    ? const CupertinoActivityIndicator(color: Colors.white)
                    : Icon(
                        Icons.power_settings_new_rounded,
                        size: 32,
                        color: isConnected ? Colors.white : (isDark ? YLColors.zinc400 : YLColors.zinc400),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrafficGrid(BuildContext context, WidgetRef ref) {
    final traffic = ref.watch(trafficProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        Expanded(
          child: YLSurface(
            padding: const EdgeInsets.all(YLSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: YLColors.connected.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.arrow_downward_rounded, size: 14, color: YLColors.connected),
                    ),
                    const SizedBox(width: YLSpacing.sm),
                    Text('Download', style: YLText.caption.copyWith(color: YLColors.zinc500)),
                  ],
                ),
                const SizedBox(height: YLSpacing.md),
                Text(
                  _formatSpeed(traffic.down),
                  style: YLText.titleLarge.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: YLSpacing.md),
        Expanded(
          child: YLSurface(
            padding: const EdgeInsets.all(YLSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: YLColors.primary.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.arrow_upward_rounded, size: 14, color: YLColors.primary),
                    ),
                    const SizedBox(width: YLSpacing.sm),
                    Text('Upload', style: YLText.caption.copyWith(color: YLColors.zinc500)),
                  ],
                ),
                const SizedBox(height: YLSpacing.md),
                Text(
                  _formatSpeed(traffic.up),
                  style: YLText.titleLarge.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSettingsGroup(BuildContext context, WidgetRef ref) {
    final routingMode = ref.watch(routingModeProvider);
    final status = ref.watch(coreStatusProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? YLColors.surfaceDark : YLColors.surfaceLight,
        borderRadius: BorderRadius.circular(YLRadius.lg),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.04),
          width: 0.5,
        ),
      ),
      child: Column(
        children: [
          // Routing Mode (Custom Pill Segmented Control)
          Padding(
            padding: const EdgeInsets.all(YLSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Routing Mode', style: YLText.body),
                const SizedBox(height: YLSpacing.md),
                YLPillSegmentedControl<String>(
                  values: const ['rule', 'global', 'direct'],
                  labels: const ['Rule', 'Global', 'Direct'],
                  selectedValue: routingMode,
                  onChanged: (mode) async {
                    ref.read(routingModeProvider.notifier).state = mode;
                    if (status == CoreStatus.running) {
                      final ok = await CoreManager.instance.api.setRoutingMode(mode);
                      if (ok) {
                        AppNotifier.success('已切换至 ${mode.toUpperCase()} 模式');
                      } else {
                        AppNotifier.error('模式切换失败');
                      }
                    }
                  },
                ),
              ],
            ),
          ),
          
          Divider(height: 1, indent: YLSpacing.lg),
          
          // System Proxy
          YLGroupedListItem(
            title: const Text('System Proxy'),
            subtitle: const Text('Set as system default proxy'),
            trailing: CupertinoSwitch(
              activeColor: YLColors.connected,
              value: ref.watch(systemProxyOnConnectProvider),
              onChanged: (val) async {
                ref.read(systemProxyOnConnectProvider.notifier).state = val;
                if (status == CoreStatus.running) {
                  if (val) {
                    await ref.read(coreActionsProvider).applySystemProxy();
                    AppNotifier.success('系统代理已开启');
                  } else {
                    await ref.read(coreActionsProvider).clearSystemProxy();
                    AppNotifier.info('系统代理已关闭');
                  }
                }
              },
            ),
          ),
          
          // TUN Mode
          YLGroupedListItem(
            title: const Text('TUN Mode'),
            subtitle: const Text('Route all traffic via virtual network'),
            isLast: true,
            trailing: CupertinoSwitch(
              activeColor: YLColors.connected,
              value: ref.watch(connectionModeProvider) == 'tun',
              onChanged: (val) {
                ref.read(connectionModeProvider.notifier).state = val ? 'tun' : 'systemProxy';
                if (status == CoreStatus.running) {
                  AppNotifier.warning('切换 TUN 模式将在下次连接时生效');
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  String _formatSpeed(int bps) {
    if (bps < 1024) return '${bps} B/s';
    if (bps < 1024 * 1024) return '${(bps / 1024).toStringAsFixed(1)} KB/s';
    return '${(bps / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
}
