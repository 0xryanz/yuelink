import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/kernel/core_manager.dart';
import '../../../i18n/app_strings.dart';
import '../../../domain/models/proxy_provider.dart';
import '../providers/proxy_providers_provider.dart';
import '../../../shared/app_notifier.dart';

class ProxyProviderPage extends ConsumerStatefulWidget {
  const ProxyProviderPage({super.key});

  @override
  ConsumerState<ProxyProviderPage> createState() =>
      _ProxyProviderPageState();
}

class _ProxyProviderPageState extends ConsumerState<ProxyProviderPage> {
  final _updatingSet = <String>{};

  @override
  void initState() {
    super.initState();
    Future.microtask(
        () => ref.read(proxyProvidersProvider.notifier).refresh());
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final providers = ref.watch(proxyProvidersProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: Text(s.proxyProviderTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.rule_folder_outlined),
            tooltip: '刷新所有规则集',
            onPressed: _refreshAllRuleProviders,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: s.retry,
            onPressed: () =>
                ref.read(proxyProvidersProvider.notifier).refresh(),
          ),
        ],
      ),
      body: providers.isEmpty
          ? Center(
              child: Text(s.proxyProviderEmpty,
                  style: Theme.of(context).textTheme.bodyMedium))
          : RefreshIndicator(
              onRefresh: () async {
                await ref
                    .read(proxyProvidersProvider.notifier)
                    .refresh();
              },
              child: ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: providers.length,
                itemBuilder: (context, index) {
                  final p = providers[index];
                  return _ProviderCard(
                    provider: p,
                    isUpdating: _updatingSet.contains(p.name),
                    onUpdate: () => _updateProvider(p.name),
                    onHealthCheck: () => _healthCheck(p.name),
                  );
                },
              ),
            ),
    );
  }

  Future<void> _updateProvider(String name) async {
    final s = S.of(context);
    setState(() => _updatingSet.add(name));
    try {
      final ok = await ref
          .read(proxyProvidersProvider.notifier)
          .update(name);
      if (ok) {
        AppNotifier.success(s.providerUpdateSuccess);
        await ref.read(proxyProvidersProvider.notifier).refresh();
      } else {
        AppNotifier.error(s.providerUpdateFailed);
      }
    } finally {
      if (mounted) setState(() => _updatingSet.remove(name));
    }
  }

  /// Refresh every rule-provider in parallel via mihomo's
  /// `PUT /providers/rules/{name}`. Rule sets (geosite, ad-block lists,
  /// custom domain groups) tend to drift faster than proxy providers —
  /// CVR exposes this; YueLink previously required a full core restart.
  Future<void> _refreshAllRuleProviders() async {
    try {
      final api = CoreManager.instance.api;
      if (!await api.isAvailable()) {
        AppNotifier.error('核心未运行，无法刷新规则集');
        return;
      }
      final result = await api.refreshAllRuleProviders();
      if (result.ok == 0 && result.failed == 0) {
        AppNotifier.warning('未找到任何规则集');
      } else if (result.failed == 0) {
        AppNotifier.success('已刷新 ${result.ok} 个规则集');
      } else {
        AppNotifier.warning(
          '刷新完成：成功 ${result.ok}，失败 ${result.failed}',
        );
      }
    } catch (e) {
      AppNotifier.error('刷新规则集失败：$e');
    }
  }

  Future<void> _healthCheck(String name) async {
    final s = S.of(context);
    setState(() => _updatingSet.add(name));
    try {
      await ref
          .read(proxyProvidersProvider.notifier)
          .healthCheck(name);
      AppNotifier.success(s.providerHealthCheckDone);
      await ref.read(proxyProvidersProvider.notifier).refresh();
    } finally {
      if (mounted) setState(() => _updatingSet.remove(name));
    }
  }
}

class _ProviderCard extends StatelessWidget {
  final ProxyProviderInfo provider;
  final bool isUpdating;
  final VoidCallback onUpdate;
  final VoidCallback onHealthCheck;

  const _ProviderCard({
    required this.provider,
    required this.isUpdating,
    required this.onUpdate,
    required this.onHealthCheck,
  });

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Icon(
          provider.vehicleType == 'HTTP'
              ? Icons.cloud_outlined
              : Icons.folder_outlined,
          size: 20,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: Text(provider.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Row(
          children: [
            _VehicleChip(type: provider.vehicleType),
            const SizedBox(width: 8),
            Text(
              s.providerNodeCount(provider.count),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        trailing: isUpdating
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.expand_more, size: 20),
        children: [
          if (provider.updatedAt != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Row(
                children: [
                  Icon(Icons.access_time,
                      size: 14,
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    _formatTime(provider.updatedAt!),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: isUpdating ? null : onUpdate,
                  icon: const Icon(Icons.sync, size: 16),
                  label: Text(s.providerUpdate),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: isUpdating ? null : onHealthCheck,
                  icon: const Icon(Icons.favorite_border, size: 16),
                  label: Text(s.providerHealthCheck),
                ),
              ],
            ),
          ),
          if (provider.proxies.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: provider.proxies.map((name) {
                  return Chip(
                    label: Text(name,
                        style: const TextStyle(fontSize: 11)),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize:
                        MaterialTapTargetSize.shrinkWrap,
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  String _formatTime(String iso) {
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}

class _VehicleChip extends StatelessWidget {
  final String type;
  const _VehicleChip({required this.type});

  @override
  Widget build(BuildContext context) {
    final color = type == 'HTTP' ? Colors.blue : Colors.teal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        type,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
