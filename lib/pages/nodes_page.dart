import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../l10n/app_strings.dart';
import '../models/proxy.dart';
import '../providers/core_provider.dart';
import '../providers/proxy_provider.dart';
import '../services/app_notifier.dart';
import '../services/core_manager.dart';
import '../services/settings_service.dart';
import '../theme.dart';

class NodesPage extends ConsumerStatefulWidget {
  const NodesPage({super.key});

  @override
  ConsumerState<NodesPage> createState() => _NodesPageState();
}

class _NodesPageState extends ConsumerState<NodesPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(proxyGroupsProvider.notifier).refresh());
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final status = ref.watch(coreStatusProvider);
    final groups = ref.watch(proxyGroupsProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (status != CoreStatus.running) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.router_outlined, size: 64, color: YLColors.zinc300),
              const SizedBox(height: YLSpacing.xl),
              Text(s.notConnectedHintProxy, style: YLText.titleLarge),
              const SizedBox(height: YLSpacing.sm),
              Text(
                s.connectToViewProxiesDesc,
                style: YLText.body.copyWith(color: YLColors.zinc500),
              ),
            ],
          ),
        ),
      );
    }

    if (groups.isEmpty) {
      return const Scaffold(
        body: Center(child: CupertinoActivityIndicator(radius: 14)),
      );
    }

    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          SliverAppBar(
            expandedHeight: 100.0,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsets.symmetric(horizontal: YLSpacing.xl, vertical: YLSpacing.lg),
              title: Text(
                s.navProxies,
                style: YLText.display.copyWith(
                  color: isDark ? Colors.white : Colors.black,
                  fontSize: 28,
                ),
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                onPressed: () => ref.read(proxyGroupsProvider.notifier).refresh(),
              ),
              const SizedBox(width: YLSpacing.sm),
            ],
          ),
          
          // ── Routing Mode ─────────────────────────────────────────
          SliverToBoxAdapter(
            child: _RoutingModeBar(),
          ),

          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: YLSpacing.xl, vertical: YLSpacing.sm),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: YLSpacing.lg),
                    child: _GroupCard(group: groups[index]),
                  );
                },
                childCount: groups.length,
              ),
            ),
          ),
          
          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }
}

class _GroupCard extends ConsumerStatefulWidget {
  final ProxyGroup group;
  const _GroupCard({required this.group});

  @override
  ConsumerState<_GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends ConsumerState<_GroupCard> with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late AnimationController _animController;
  late Animation<double> _expandAnim;
  late Animation<double> _chevronAnim;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
      value: 0.0,
    );
    _expandAnim = CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic);
    _chevronAnim = Tween<double>(begin: 0, end: 0.5).animate(_expandAnim);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _animController.forward();
    } else {
      _animController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final delays = ref.watch(delayResultsProvider);
    final testing = ref.watch(delayTestingProvider);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? YLColors.zinc900 : Colors.white,
        borderRadius: BorderRadius.circular(YLRadius.xl),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.04),
          width: 0.5,
        ),
        boxShadow: isDark ? [] : [
          BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(YLRadius.xl),
              bottom: _expanded ? Radius.zero : const Radius.circular(YLRadius.xl),
            ),
            child: Padding(
              padding: const EdgeInsets.all(YLSpacing.md),
              child: Row(
                children: [
                  RotationTransition(
                    turns: _chevronAnim,
                    child: Icon(Icons.expand_more_rounded, size: 20, color: YLColors.zinc400),
                  ),
                  const SizedBox(width: YLSpacing.sm),
                  Text(group.name, style: YLText.titleMedium),
                  const SizedBox(width: YLSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isDark ? YLColors.zinc800 : YLColors.zinc100,
                      borderRadius: BorderRadius.circular(YLRadius.sm),
                    ),
                    child: Text(
                      group.type,
                      style: YLText.caption.copyWith(fontSize: 10, color: YLColors.zinc500, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    S.of(context).nodesCountLabel(group.all.length),
                    style: YLText.caption.copyWith(color: YLColors.zinc500),
                  ),
                  const SizedBox(width: YLSpacing.sm),
                  IconButton(
                    onPressed: testing.isNotEmpty
                        ? null
                        : () {
                            ref.read(delayTestProvider).testGroup(group.name, group.all);
                            AppNotifier.info(S.of(context).testingGroup(group.name));
                          },
                    icon: testing.isNotEmpty
                        ? const CupertinoActivityIndicator(radius: 7)
                        : const Icon(Icons.bolt_rounded),
                    iconSize: 18,
                    color: YLColors.primary,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ),

          // List
          SizeTransition(
            sizeFactor: _expandAnim,
            axisAlignment: -1.0,
            child: Column(
              children: [
                Divider(height: 0.5),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: YLSpacing.xs),
                  child: Column(
                    children: List.generate(group.all.length, (i) {
                      final nodeName = group.all[i];
                      final isSelected = nodeName == group.now;
                      return Column(
                        children: [
                          _NodeTile(
                            name: nodeName,
                            isSelected: isSelected,
                            delay: delays[nodeName],
                            isTesting: testing.contains(nodeName),
                            onSelect: () async {
                              final ok = await ref.read(proxyGroupsProvider.notifier).changeProxy(group.name, nodeName);
                              if (ok) {
                                AppNotifier.success(S.of(context).switchedTo(nodeName));
                                ref.read(proxyGroupsProvider.notifier).refresh();
                              } else {
                                AppNotifier.error(S.of(context).switchFailed);
                              }
                              return ok;
                            },
                            onTest: () => ref.read(delayTestProvider).testDelay(nodeName),
                          ),
                          if (i < group.all.length - 1)
                            Divider(height: 1, indent: 48),
                        ],
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NodeTile extends StatefulWidget {
  final String name;
  final bool isSelected;
  final int? delay;
  final bool isTesting;
  final Future<bool> Function() onSelect;
  final VoidCallback onTest;

  const _NodeTile({
    required this.name,
    required this.isSelected,
    this.delay,
    required this.isTesting,
    required this.onSelect,
    required this.onTest,
  });

  @override
  State<_NodeTile> createState() => _NodeTileState();
}

// ── Routing Mode Bar ────────────────────────────────────────────────────────

class _RoutingModeBar extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final routingMode = ref.watch(routingModeProvider);
    final status = ref.watch(coreStatusProvider);

    return Padding(
      padding: const EdgeInsets.fromLTRB(YLSpacing.xl, 0, YLSpacing.xl, YLSpacing.sm),
      child: YLPillSegmentedControl<String>(
        values: const ['rule', 'global', 'direct'],
        labels: [s.routeModeRule, s.routeModeGlobal, s.routeModeDirect],
        selectedValue: routingMode,
        onChanged: (mode) async {
          ref.read(routingModeProvider.notifier).state = mode;
          await SettingsService.setRoutingMode(mode);
          if (status == CoreStatus.running) {
            try {
              await CoreManager.instance.api.setRoutingMode(mode);
            } catch (_) {}
          }
        },
      ),
    );
  }
}

// ── Node Tile ───────────────────────────────────────────────────────────────

class _NodeTileState extends State<_NodeTile> {
  bool _isSwitching = false;

  void _handleSelect() async {
    if (_isSwitching || widget.isSelected) return;
    setState(() => _isSwitching = true);
    await widget.onSelect();
    if (mounted) setState(() => _isSwitching = false);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _handleSelect,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: YLSpacing.md, vertical: YLSpacing.sm),
          color: widget.isSelected 
              ? (isDark ? YLColors.primary.withOpacity(0.1) : YLColors.primary.withOpacity(0.05))
              : Colors.transparent,
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: _isSwitching
                    ? const CupertinoActivityIndicator(radius: 7)
                    : (widget.isSelected
                        ? const Icon(Icons.check_rounded, color: YLColors.primary, size: 18)
                        : null),
              ),
              const SizedBox(width: YLSpacing.xs),
              Expanded(
                child: Text(
                  widget.name,
                  style: YLText.body.copyWith(
                    fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: widget.isSelected 
                        ? YLColors.primary 
                        : (isDark ? Colors.white : Colors.black),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: YLSpacing.sm),
              InkWell(
                onTap: widget.isTesting ? null : widget.onTest,
                borderRadius: BorderRadius.circular(YLRadius.sm),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: YLDelayBadge(delay: widget.delay, testing: widget.isTesting),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
