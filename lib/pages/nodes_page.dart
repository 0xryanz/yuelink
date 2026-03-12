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

/// Sort a list of node names based on the given sort mode and delay map.
List<String> _sortedNodes(
    List<String> nodes, NodeSortMode mode, Map<String, int> delays) {
  switch (mode) {
    case NodeSortMode.defaultOrder:
      return nodes;
    case NodeSortMode.nameAsc:
      final copy = List<String>.from(nodes)..sort();
      return copy;
    case NodeSortMode.latencyAsc:
      final copy = List<String>.from(nodes);
      copy.sort((a, b) {
        final da = delays[a];
        final db = delays[b];
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        if (da < 0 && db < 0) return 0;
        if (da < 0) return 1;
        if (db < 0) return -1;
        return da.compareTo(db);
      });
      return copy;
    case NodeSortMode.latencyDesc:
      final copy = List<String>.from(nodes);
      copy.sort((a, b) {
        final da = delays[a];
        final db = delays[b];
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        if (da < 0 && db < 0) return 0;
        if (da < 0) return 1;
        if (db < 0) return -1;
        return db.compareTo(da);
      });
      return copy;
  }
}

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
    final routingMode = ref.watch(routingModeProvider);
    final globalGroup = ref.watch(globalGroupProvider);

    if (status != CoreStatus.running) {
      final offlineGroups = ref.watch(offlineProxyGroupsProvider);
      return Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics()),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                        YLSpacing.xl, YLSpacing.xl, YLSpacing.xl, YLSpacing.md),
                    child: Column(
                      children: [
                        Icon(Icons.router_outlined,
                            size: 64, color: YLColors.zinc300),
                        const SizedBox(height: YLSpacing.xl),
                        Text(s.notConnectedHintProxy,
                            style: YLText.titleLarge),
                        const SizedBox(height: YLSpacing.sm),
                        Text(
                          s.connectToViewProxiesDesc,
                          style:
                              YLText.body.copyWith(color: YLColors.zinc500),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
                offlineGroups.when(
                  data: (groups) {
                    if (groups.isEmpty) {
                      return const SliverToBoxAdapter(child: SizedBox.shrink());
                    }
                    return SliverList(
                      delegate: SliverChildListDelegate([
                        // Offline preview banner
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                              YLSpacing.xl, 0, YLSpacing.xl, YLSpacing.md),
                          child: _OfflinePreviewBanner(s.offlinePreview),
                        ),
                        ...groups.map((g) => Padding(
                              padding: const EdgeInsets.fromLTRB(
                                  YLSpacing.xl,
                                  0,
                                  YLSpacing.xl,
                                  YLSpacing.lg),
                              child: _ReadOnlyGroupCard(group: g),
                            )),
                      ]),
                    );
                  },
                  loading: () =>
                      const SliverToBoxAdapter(child: SizedBox.shrink()),
                  error: (_, __) =>
                      const SliverToBoxAdapter(child: SizedBox.shrink()),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
          ),
        ),
      );
    }

    if (groups.isEmpty && globalGroup == null) {
      return const Scaffold(
        body: Center(child: CupertinoActivityIndicator(radius: 14)),
      );
    }

    // ── Direct mode: no proxy group selection needed ──────────────────
    if (routingMode == 'direct') {
      return Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics()),
              slivers: [
                SliverAppBar(
                  backgroundColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  pinned: true,
                  actions: [
                    _CompactRoutingMode(),
                    const SizedBox(width: YLSpacing.sm),
                  ],
                ),
                SliverFillRemaining(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.link_rounded,
                          size: 56, color: YLColors.zinc300),
                      const SizedBox(height: YLSpacing.lg),
                      Text(s.routeModeDirect,
                          style: YLText.titleLarge),
                      const SizedBox(height: YLSpacing.sm),
                      Text(
                        s.directModeDesc,
                        style:
                            YLText.body.copyWith(color: YLColors.zinc500),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ── Global mode: show only the GLOBAL group ───────────────────────
    if (routingMode == 'global') {
      final globalSortMode = ref.watch(nodeSortModeProvider);
      final globalDelays = ref.watch(delayResultsProvider);
      return Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(
                  parent: AlwaysScrollableScrollPhysics()),
              slivers: [
                SliverAppBar(
                  backgroundColor: Colors.transparent,
                  surfaceTintColor: Colors.transparent,
                  pinned: true,
                  actions: [
                    _CompactRoutingMode(),
                    const SizedBox(width: 4),
                    // Sort button
                    IconButton(
                      icon: const Icon(Icons.sort_rounded),
                      iconSize: 20,
                      tooltip: _sortModeLabel(s, globalSortMode),
                      onPressed: () {
                        final modes = NodeSortMode.values;
                        final next = modes[
                            (globalSortMode.index + 1) % modes.length];
                        ref.read(nodeSortModeProvider.notifier).state = next;
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded),
                      onPressed: () =>
                          ref.read(proxyGroupsProvider.notifier).refresh(),
                    ),
                    const SizedBox(width: YLSpacing.sm),
                  ],
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                      YLSpacing.xl, YLSpacing.sm, YLSpacing.xl, 0),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _ModeBanner(
                        icon: Icons.public_rounded,
                        text: s.globalModeDesc,
                      ),
                      const SizedBox(height: YLSpacing.lg),
                      if (globalGroup != null)
                        _GroupCard(
                          group: globalGroup,
                          sortedNodes: _sortedNodes(
                              globalGroup.all, globalSortMode, globalDelays),
                        ),
                    ]),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 100)),
              ],
            ),
          ),
        ),
      );
    }

    // ── Rule mode: show all groups (default) ──────────────────────────
    final sortMode = ref.watch(nodeSortModeProvider);
    final viewMode = ref.watch(nodeViewModeProvider);
    final delays = ref.watch(delayResultsProvider);

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: CustomScrollView(
            physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics()),
            slivers: [
              SliverAppBar(
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                pinned: true,
                actions: [
                  _CompactRoutingMode(),
                  const SizedBox(width: 4),
                  // Sort button
                  IconButton(
                    icon: const Icon(Icons.sort_rounded),
                    iconSize: 20,
                    tooltip: _sortModeLabel(s, sortMode),
                    onPressed: () {
                      final modes = NodeSortMode.values;
                      final next =
                          modes[(sortMode.index + 1) % modes.length];
                      ref.read(nodeSortModeProvider.notifier).state = next;
                    },
                  ),
                  // Layout toggle button
                  IconButton(
                    icon: Icon(viewMode == NodeViewMode.card
                        ? Icons.view_list_rounded
                        : Icons.grid_view_rounded),
                    iconSize: 20,
                    tooltip: viewMode == NodeViewMode.card
                        ? s.nodeViewList
                        : s.nodeViewCard,
                    onPressed: () {
                      ref.read(nodeViewModeProvider.notifier).state =
                          viewMode == NodeViewMode.card
                              ? NodeViewMode.list
                              : NodeViewMode.card;
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: () =>
                        ref.read(proxyGroupsProvider.notifier).refresh(),
                  ),
                  const SizedBox(width: YLSpacing.sm),
                ],
              ),

              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                    YLSpacing.xl, YLSpacing.sm, YLSpacing.xl, 0),
                sliver: viewMode == NodeViewMode.list
                    ? SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final group = groups[index];
                            final sorted = _sortedNodes(
                                group.all, sortMode, delays);
                            return Padding(
                              padding: const EdgeInsets.only(
                                  bottom: YLSpacing.lg),
                              child: _GroupListSection(
                                group: group,
                                sortedNodes: sorted,
                              ),
                            );
                          },
                          childCount: groups.length,
                        ),
                      )
                    : SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (context, index) {
                            final group = groups[index];
                            final sorted = _sortedNodes(
                                group.all, sortMode, delays);
                            return Padding(
                              padding: const EdgeInsets.only(
                                  bottom: YLSpacing.lg),
                              child: _GroupCard(
                                  group: group, sortedNodes: sorted),
                            );
                          },
                          childCount: groups.length,
                        ),
                      ),
              ),

              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
        ),
      ),
    );
  }
}

String _sortModeLabel(S s, NodeSortMode mode) {
  switch (mode) {
    case NodeSortMode.defaultOrder:
      return s.sortDefault;
    case NodeSortMode.latencyAsc:
      return s.sortLatencyAsc;
    case NodeSortMode.latencyDesc:
      return s.sortLatencyDesc;
    case NodeSortMode.nameAsc:
      return s.sortNameAsc;
  }
}

// ── Mode banner ────────────────────────────────────────────────────────────

class _ModeBanner extends StatelessWidget {
  const _ModeBanner({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: YLSpacing.lg, vertical: YLSpacing.md),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(YLRadius.lg),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: YLColors.zinc500),
          const SizedBox(width: YLSpacing.sm),
          Expanded(
            child: Text(text,
                style: YLText.caption.copyWith(color: YLColors.zinc500)),
          ),
        ],
      ),
    );
  }
}

class _GroupCard extends ConsumerStatefulWidget {
  final ProxyGroup group;
  final List<String>? sortedNodes;
  const _GroupCard({required this.group, this.sortedNodes});

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
          color: isDark ? Colors.white.withValues(alpha:0.08) : Colors.black.withValues(alpha:0.04),
          width: 0.5,
        ),
        boxShadow: YLShadow.card(context),
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
                    color: isDark ? Colors.white : YLColors.primary,
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
                    children: List.generate((widget.sortedNodes ?? group.all).length, (i) {
                      final nodeList = widget.sortedNodes ?? group.all;
                      final nodeName = nodeList[i];
                      final isSelected = nodeName == group.now;
                      return Column(
                        children: [
                          _NodeTile(
                            name: nodeName,
                            isSelected: isSelected,
                            delay: delays[nodeName],
                            isTesting: testing.contains(nodeName),
                            onSelect: () async {
                              final s = S.of(context);
                              final ok = await ref.read(proxyGroupsProvider.notifier).changeProxy(group.name, nodeName);
                              if (ok) {
                                AppNotifier.success(s.switchedTo(nodeName));
                              } else {
                                AppNotifier.error(s.switchFailed);
                              }
                              return ok;
                            },
                            onTest: () => ref.read(delayTestProvider).testDelay(nodeName),
                          ),
                          if (i < (widget.sortedNodes ?? group.all).length - 1)
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

// ── Compact Routing Mode (AppBar) ────────────────────────────────────────────

class _CompactRoutingMode extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final routingMode = ref.watch(routingModeProvider);
    final status = ref.watch(coreStatusProvider);

    const modes = ['rule', 'global', 'direct'];
    final labels = [s.routeModeRule, s.routeModeGlobal, s.routeModeDirect];

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 200),
      child: Container(
        height: 32,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(YLRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(modes.length, (i) {
            final isSelected = modes[i] == routingMode;
            return Flexible(
              child: GestureDetector(
                onTap: () async {
                  final mode = modes[i];
                  ref.read(routingModeProvider.notifier).state = mode;
                  await SettingsService.setRoutingMode(mode);
                  if (status == CoreStatus.running) {
                    try {
                      final ok = await CoreManager.instance.api.setRoutingMode(mode);
                      if (ok) {
                        // Close all connections when switching to direct
                        if (mode == 'direct') {
                          try {
                            await CoreManager.instance.api
                                .closeAllConnections();
                          } catch (_) {}
                        }
                        // Refresh proxy groups to reflect new mode
                        ref.read(proxyGroupsProvider.notifier).refresh();
                        // Verify and show feedback
                        final actual = await CoreManager.instance.api.getRoutingMode();
                        debugPrint('[RoutingMode] set=$mode, actual=$actual');
                        if (actual != mode) {
                          AppNotifier.warning('${s.routeModeRule}: $actual ≠ $mode');
                        } else {
                          final modeLabel = mode == 'global'
                              ? s.routeModeGlobal
                              : mode == 'direct'
                                  ? s.routeModeDirect
                                  : s.routeModeRule;
                          AppNotifier.success('${s.modeSwitched}: $modeLabel');
                        }
                      } else {
                        AppNotifier.error(s.switchModeFailed);
                        // Revert UI state
                        ref.read(routingModeProvider.notifier).state = routingMode;
                      }
                    } catch (e) {
                      debugPrint('[RoutingMode] error: $e');
                      AppNotifier.error('${s.switchModeFailed}: $e');
                      ref.read(routingModeProvider.notifier).state = routingMode;
                    }
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? (isDark ? YLColors.zinc700 : Colors.white)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(YLRadius.pill),
                    boxShadow: isSelected ? YLShadow.sm(context) : [],
                  ),
                  child: Text(
                    labels[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: YLText.caption.copyWith(
                      fontSize: 11,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected
                          ? (isDark ? Colors.white : Colors.black)
                          : YLColors.zinc500,
                    ),
                  ),
                ),
              ),
            );
          }),
        ),
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
              ? (isDark ? Colors.white.withValues(alpha:0.08) : YLColors.primary.withValues(alpha:0.05))
              : Colors.transparent,
          child: Row(
            children: [
              SizedBox(
                width: 24,
                child: _isSwitching
                    ? const CupertinoActivityIndicator(radius: 7)
                    : (widget.isSelected
                        ? Icon(Icons.check_rounded, color: isDark ? Colors.white : YLColors.primary, size: 18)
                        : null),
              ),
              const SizedBox(width: YLSpacing.xs),
              Expanded(
                child: Text(
                  widget.name,
                  style: YLText.body.copyWith(
                    fontWeight: widget.isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: widget.isSelected
                        ? (isDark ? Colors.white : YLColors.primary)
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

// ── Offline Preview Banner ──────────────────────────────────────────────────

class _OfflinePreviewBanner extends StatelessWidget {
  final String message;
  const _OfflinePreviewBanner(this.message);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: YLSpacing.lg, vertical: YLSpacing.sm),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.amber.withValues(alpha: 0.10)
            : Colors.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(YLRadius.lg),
        border: Border.all(
          color: Colors.amber.withValues(alpha: 0.25),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              size: 14, color: Colors.amber),
          const SizedBox(width: YLSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: YLText.caption.copyWith(color: Colors.amber.shade700),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Read-Only Group Card (offline preview) ──────────────────────────────────

class _ReadOnlyGroupCard extends StatelessWidget {
  final ProxyGroup group;
  const _ReadOnlyGroupCard({required this.group});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? YLColors.zinc900 : Colors.white,
        borderRadius: BorderRadius.circular(YLRadius.xl),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.04),
          width: 0.5,
        ),
        boxShadow: YLShadow.card(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(YLSpacing.md),
            child: Row(
              children: [
                const Icon(Icons.expand_more_rounded,
                    size: 20, color: YLColors.zinc400),
                const SizedBox(width: YLSpacing.sm),
                Text(group.name, style: YLText.titleMedium),
                const SizedBox(width: YLSpacing.sm),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDark ? YLColors.zinc800 : YLColors.zinc100,
                    borderRadius: BorderRadius.circular(YLRadius.sm),
                  ),
                  child: Text(
                    group.type,
                    style: YLText.caption.copyWith(
                        fontSize: 10,
                        color: YLColors.zinc500,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                const Spacer(),
                Text(
                  S.of(context).nodesCountLabel(group.all.length),
                  style: YLText.caption.copyWith(color: YLColors.zinc500),
                ),
              ],
            ),
          ),
          if (group.all.isNotEmpty) ...[
            const Divider(height: 0.5),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: YLSpacing.xs),
              child: Column(
                children: List.generate(group.all.length, (i) {
                  final name = group.all[i];
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: YLSpacing.md, vertical: YLSpacing.sm),
                        child: Row(
                          children: [
                            const SizedBox(width: 24),
                            const SizedBox(width: YLSpacing.xs),
                            Expanded(
                              child: Text(
                                name,
                                style: YLText.body.copyWith(
                                    color: isDark
                                        ? Colors.white70
                                        : YLColors.zinc700),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (i < group.all.length - 1)
                        const Divider(height: 1, indent: 48),
                    ],
                  );
                }),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Group List Section (flat list view) ────────────────────────────────────

class _GroupListSection extends ConsumerWidget {
  final ProxyGroup group;
  final List<String> sortedNodes;
  const _GroupListSection(
      {required this.group, required this.sortedNodes});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final delays = ref.watch(delayResultsProvider);
    final testing = ref.watch(delayTestingProvider);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? YLColors.zinc900 : Colors.white,
        borderRadius: BorderRadius.circular(YLRadius.xl),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : Colors.black.withValues(alpha: 0.04),
          width: 0.5,
        ),
        boxShadow: YLShadow.card(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Group header (non-expandable)
          Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: YLSpacing.md, vertical: YLSpacing.sm),
            child: Row(
              children: [
                Text(group.name, style: YLText.titleMedium),
                const SizedBox(width: YLSpacing.sm),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isDark ? YLColors.zinc800 : YLColors.zinc100,
                    borderRadius: BorderRadius.circular(YLRadius.sm),
                  ),
                  child: Text(
                    group.type,
                    style: YLText.caption.copyWith(
                        fontSize: 10,
                        color: YLColors.zinc500,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                const Spacer(),
                Text(
                  S.of(context).nodesCountLabel(sortedNodes.length),
                  style: YLText.caption.copyWith(color: YLColors.zinc500),
                ),
              ],
            ),
          ),
          const Divider(height: 0.5),
          // Flat node list
          Column(
            children: List.generate(sortedNodes.length, (i) {
              final nodeName = sortedNodes[i];
              final isSelected = nodeName == group.now;
              return Column(
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () async {
                        final s = S.of(context);
                        final ok = await ref
                            .read(proxyGroupsProvider.notifier)
                            .changeProxy(group.name, nodeName);
                        if (ok) {
                          AppNotifier.success(s.switchedTo(nodeName));
                        } else {
                          AppNotifier.error(s.switchFailed);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: YLSpacing.md,
                            vertical: YLSpacing.sm),
                        color: isSelected
                            ? (isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : YLColors.primary.withValues(alpha: 0.05))
                            : Colors.transparent,
                        child: Row(
                          children: [
                            SizedBox(
                              width: 24,
                              child: isSelected
                                  ? Icon(Icons.check_rounded,
                                      size: 16,
                                      color: isDark
                                          ? Colors.white
                                          : YLColors.primary)
                                  : null,
                            ),
                            const SizedBox(width: YLSpacing.xs),
                            Expanded(
                              child: Text(
                                nodeName,
                                style: YLText.body.copyWith(
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: isSelected
                                      ? (isDark
                                          ? Colors.white
                                          : YLColors.primary)
                                      : (isDark
                                          ? Colors.white
                                          : Colors.black),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            YLDelayBadge(
                              delay: delays[nodeName],
                              testing: testing.contains(nodeName),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (i < sortedNodes.length - 1)
                    const Divider(height: 1, indent: 48),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}
