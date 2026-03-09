import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/proxy.dart';
import '../providers/core_provider.dart';
import '../providers/proxy_provider.dart';

class ProxyPage extends ConsumerStatefulWidget {
  const ProxyPage({super.key});

  @override
  ConsumerState<ProxyPage> createState() => _ProxyPageState();
}

class _ProxyPageState extends ConsumerState<ProxyPage> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(proxyGroupsProvider.notifier).refresh());
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

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async {
          ref.read(proxyGroupsProvider.notifier).refresh();
        },
        child: ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: groups.length,
          itemBuilder: (context, index) {
            return _ProxyGroupCard(group: groups[index]);
          },
        ),
      ),
    );
  }
}

class _ProxyGroupCard extends ConsumerWidget {
  final ProxyGroup group;
  const _ProxyGroupCard({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final delays = ref.watch(delayResultsProvider);
    final testing = ref.watch(delayTestingProvider);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
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
              children: group.all.map((name) {
                final isSelected = name == group.now;
                final delay = delays[name];
                final isTesting = testing.contains(name);

                return ChoiceChip(
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
                            child: CircularProgressIndicator(strokeWidth: 1.5),
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
                      ? () => ref
                          .read(delayTestProvider)
                          .testGroup(group.all)
                      : null,
                  icon: const Icon(Icons.speed, size: 16),
                  label: Text(
                      testing.isEmpty ? '测速全部' : '测速中 (${testing.length})'),
                ),
                const Spacer(),
                Text('${group.all.length} 个节点',
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
