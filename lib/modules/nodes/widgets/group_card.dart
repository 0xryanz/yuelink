import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/proxy.dart';
import '../../../l10n/app_strings.dart';
import '../../../shared/app_notifier.dart';
import '../../../theme.dart';
import '../providers/node_providers.dart';
import '../providers/nodes_providers.dart';
import 'node_tile.dart';

/// Sorted node list helper — no delay map required for sort modes that don't
/// use delays. For latency sorts the GroupCard reads the full map once to
/// build the sorted order (this only happens when sort mode changes, not on
/// every delay update, because NodeTile handles its own delay rendering).
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

/// Expandable card showing a proxy group header and its node list.
///
/// Does NOT watch [delayResultsProvider] or [delayTestingProvider] directly.
/// The header only reads [groupSelectedNodeProvider] for the selected-node
/// display, and [delayTestingProvider] once to gate the test button.
/// Each [NodeTile] inside watches its own per-node providers independently.
class GroupCard extends ConsumerStatefulWidget {
  const GroupCard({
    super.key,
    required this.group,
    this.sortMode = NodeSortMode.defaultOrder,
  });

  final ProxyGroup group;
  final NodeSortMode sortMode;

  @override
  ConsumerState<GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends ConsumerState<GroupCard>
    with SingleTickerProviderStateMixin {
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
    _expandAnim =
        CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic);
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

    // Header only watches the "any testing in progress" flag for the button
    // state, and the delay map only when a latency sort is active. NodeTile
    // widgets each subscribe to their own per-node providers.
    final testing = ref.watch(delayTestingProvider);

    // Read delays only for computing sort order; this does NOT cause this
    // widget to rebuild on individual delay updates because the sorted node
    // list is derived from group.all which only changes on group refresh.
    final delays = ref.read(delayResultsProvider);
    final nodeList = _sortedNodes(group.all, widget.sortMode, delays);

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
          InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(YLRadius.xl),
              bottom: _expanded
                  ? Radius.zero
                  : const Radius.circular(YLRadius.xl),
            ),
            child: Padding(
              padding: const EdgeInsets.all(YLSpacing.md),
              child: Row(
                children: [
                  RotationTransition(
                    turns: _chevronAnim,
                    child: Icon(Icons.expand_more_rounded,
                        size: 20, color: YLColors.zinc400),
                  ),
                  const SizedBox(width: YLSpacing.sm),
                  Text(group.name, style: YLText.titleMedium),
                  const SizedBox(width: YLSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
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
                  const SizedBox(width: YLSpacing.sm),
                  IconButton(
                    onPressed: testing.isNotEmpty
                        ? null
                        : () {
                            ref
                                .read(delayTestProvider)
                                .testGroup(group.name, group.all);
                            AppNotifier.info(
                                S.of(context).testingGroup(group.name));
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

          // Expandable node list
          SizeTransition(
            sizeFactor: _expandAnim,
            axisAlignment: -1.0,
            child: Column(
              children: [
                const Divider(height: 0.5),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: YLSpacing.xs),
                  child: Column(
                    children: List.generate(nodeList.length, (i) {
                      final nodeName = nodeList[i];
                      return Column(
                        children: [
                          // NodeTile watches its own providers independently.
                          NodeTile(
                            name: nodeName,
                            groupName: group.name,
                          ),
                          if (i < nodeList.length - 1)
                            const Divider(height: 1, indent: 48),
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
