import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/proxy.dart';
import '../providers/core_provider.dart';
import '../providers/proxy_provider.dart';

enum _SortMode { none, delay }

class ProxyPage extends ConsumerStatefulWidget {
  const ProxyPage({super.key});

  @override
  ConsumerState<ProxyPage> createState() => _ProxyPageState();
}

class _ProxyPageState extends ConsumerState<ProxyPage> {
  String _searchQuery = '';
  _SortMode _sortMode = _SortMode.none;
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(proxyGroupsProvider.notifier).refresh());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(proxyGroupsProvider);
    final status = ref.watch(coreStatusProvider);

    if (status != CoreStatus.running) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.dns_outlined,
                  size: 64,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text('请先连接以查看代理节点',
                  style: Theme.of(context).textTheme.bodyLarge),
            ],
          ),
        ),
      );
    }

    if (groups.isEmpty) {
      return Scaffold(
        body: const Center(child: CircularProgressIndicator()),
        floatingActionButton: FloatingActionButton.small(
          onPressed: () => ref.read(proxyGroupsProvider.notifier).refresh(),
          child: const Icon(Icons.refresh),
        ),
      );
    }

    final filteredGroups = _filterGroups(groups);

    return Scaffold(
      body: Column(
        children: [
          // Search bar + sort toggle
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: '搜索节点...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v.trim()),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(() {
                    _sortMode = _sortMode == _SortMode.none
                        ? _SortMode.delay
                        : _SortMode.none;
                  }),
                  icon: Icon(
                    Icons.sort,
                    size: 20,
                    color: _sortMode == _SortMode.delay
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                  tooltip: _sortMode == _SortMode.delay ? '取消排序' : '按延迟排序',
                ),
              ],
            ),
          ),

          // Group list
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                ref.read(proxyGroupsProvider.notifier).refresh();
              },
              child: filteredGroups.isEmpty
                  ? Center(
                      child: Text('未找到匹配的节点',
                          style: Theme.of(context).textTheme.bodyMedium))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      itemCount: filteredGroups.length,
                      itemBuilder: (context, index) {
                        return _ProxyGroupCard(
                          group: filteredGroups[index],
                          searchQuery: _searchQuery,
                          sortMode: _sortMode,
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  List<ProxyGroup> _filterGroups(List<ProxyGroup> groups) {
    if (_searchQuery.isEmpty) return groups;
    final q = _searchQuery.toLowerCase();
    return groups
        .where((g) =>
            g.name.toLowerCase().contains(q) ||
            g.all.any((n) => n.toLowerCase().contains(q)))
        .toList();
  }
}

class _ProxyGroupCard extends ConsumerWidget {
  final ProxyGroup group;
  final String searchQuery;
  final _SortMode sortMode;

  const _ProxyGroupCard({
    required this.group,
    required this.searchQuery,
    required this.sortMode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final delays = ref.watch(delayResultsProvider);
    final testing = ref.watch(delayTestingProvider);

    // Filter nodes if searching
    var visibleNodes = searchQuery.isEmpty
        ? List<String>.from(group.all)
        : group.all
            .where(
                (n) => n.toLowerCase().contains(searchQuery.toLowerCase()))
            .toList();

    // Sort by delay if enabled
    if (sortMode == _SortMode.delay) {
      visibleNodes.sort((a, b) {
        final da = delays[a];
        final db = delays[b];
        // Untested nodes go to end
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        // Timeout (<=0) goes after valid delays
        if (da <= 0 && db <= 0) return 0;
        if (da <= 0) return 1;
        if (db <= 0) return -1;
        return da.compareTo(db);
      });
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        initiallyExpanded: searchQuery.isNotEmpty,
        title: Text(group.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Row(
          children: [
            _TypeChip(type: group.type),
            const SizedBox(width: 8),
            Flexible(
              child: Text(group.now,
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: visibleNodes.map((name) {
                final isSelected = name == group.now;
                final delay = delays[name];
                final isTesting = testing.contains(name);

                return GestureDetector(
                  onLongPress: isTesting
                      ? null
                      : () => ref.read(delayTestProvider).testDelay(name),
                  child: ChoiceChip(
                    label: SizedBox(
                      width: 100,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(name,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12)),
                          const SizedBox(height: 2),
                          if (isTesting)
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child:
                                  CircularProgressIndicator(strokeWidth: 1.5),
                            )
                          else if (delay != null)
                            Text(
                              delay > 0 ? '${delay}ms' : 'timeout',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: _delayColor(delay),
                              ),
                            )
                          else
                            Text('--',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant)),
                        ],
                      ),
                    ),
                    selected: isSelected,
                    onSelected: (_) {
                      ref
                          .read(proxyGroupsProvider.notifier)
                          .changeProxy(group.name, name);
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: testing.isEmpty
                      ? () =>
                          ref.read(delayTestProvider).testGroup(visibleNodes)
                      : null,
                  icon: const Icon(Icons.speed, size: 16),
                  label: Text(testing.isEmpty
                      ? '测速全部'
                      : '测速中 (${testing.length})'),
                ),
                const Spacer(),
                Text('${visibleNodes.length}/${group.all.length} 节点',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _delayColor(int delay) {
    if (delay <= 0) return Colors.red;
    if (delay < 100) return Colors.green;
    if (delay < 300) return Colors.lightGreen;
    if (delay < 500) return Colors.orange;
    return Colors.red;
  }
}

class _TypeChip extends StatelessWidget {
  final String type;
  const _TypeChip({required this.type});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        type,
        style: TextStyle(
          fontSize: 10,
          color: Theme.of(context).colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}
