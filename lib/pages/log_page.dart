import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/core_controller.dart';
import '../models/rule.dart';
import '../models/traffic.dart';
import '../providers/core_provider.dart';
import '../providers/log_provider.dart';
import '../providers/rule_provider.dart';
import '../services/core_manager.dart';
import '../services/mihomo_stream.dart';
import '../services/subscription_parser.dart';

class LogPage extends ConsumerStatefulWidget {
  const LogPage({super.key});

  @override
  ConsumerState<LogPage> createState() => _LogPageState();
}

class _LogPageState extends ConsumerState<LogPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(coreStatusProvider);
    final isRunning = status == CoreStatus.running;

    if (!isRunning) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.list_alt_outlined,
                  size: 64,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text('请先连接以查看日志',
                  style: Theme.of(context).textTheme.bodyLarge),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Column(
        children: [
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(text: '连接'),
              Tab(text: '日志'),
              Tab(text: '规则'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                _ConnectionsTab(),
                _LogsTab(),
                _RulesTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ==================================================================
// Connections tab
// ==================================================================

class _ConnectionsTab extends ConsumerStatefulWidget {
  const _ConnectionsTab();

  @override
  ConsumerState<_ConnectionsTab> createState() => _ConnectionsTabState();
}

class _ConnectionsTabState extends ConsumerState<_ConnectionsTab> {
  List<ConnectionInfo> _connections = [];
  int _uploadTotal = 0;
  int _downloadTotal = 0;
  Timer? _refreshTimer;
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _refresh();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) _refresh();
    });
  }

  Future<void> _refresh() async {
    final manager = CoreManager.instance;
    Map<String, dynamic> data;

    if (manager.isMockMode) {
      data = CoreController.instance.getConnections();
    } else {
      try {
        data = await manager.api.getConnections();
      } catch (_) {
        return;
      }
    }

    final conns = (data['connections'] as List?)
            ?.map((e) => ConnectionInfo.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    if (mounted) {
      setState(() {
        _connections = conns;
        _uploadTotal = (data['uploadTotal'] as num?)?.toInt() ?? 0;
        _downloadTotal = (data['downloadTotal'] as num?)?.toInt() ?? 0;
      });
    }
  }

  Future<void> _closeConnection(String id) async {
    final manager = CoreManager.instance;
    if (manager.isMockMode) {
      CoreController.instance.closeConnection(id);
    } else {
      await manager.api.closeConnection(id);
    }
  }

  Future<void> _closeAllConnections() async {
    final manager = CoreManager.instance;
    if (manager.isMockMode) {
      CoreController.instance.closeAllConnections();
    } else {
      await manager.api.closeAllConnections();
    }
  }

  List<ConnectionInfo> get _filteredConnections {
    if (_searchQuery.isEmpty) return _connections;
    final q = _searchQuery.toLowerCase();
    return _connections
        .where((c) =>
            c.host.toLowerCase().contains(q) ||
            c.rule.toLowerCase().contains(q) ||
            c.chains.toLowerCase().contains(q) ||
            c.network.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredConnections;

    return Column(
      children: [
        // Summary bar
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StatChip(
                icon: Icons.arrow_upward,
                iconColor: Colors.blue,
                label: '总上传',
                value: formatBytes(_uploadTotal),
              ),
              _StatChip(
                icon: Icons.arrow_downward,
                iconColor: Colors.green,
                label: '总下载',
                value: formatBytes(_downloadTotal),
              ),
              _StatChip(
                icon: Icons.link,
                iconColor: Theme.of(context).colorScheme.primary,
                label: '连接数',
                value: '${_connections.length}',
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // Search + action bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: '搜索连接...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? GestureDetector(
                              onTap: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                              child: const Icon(Icons.clear, size: 16),
                            )
                          : null,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                    ),
                    style: const TextStyle(fontSize: 13),
                    onChanged: (v) =>
                        setState(() => _searchQuery = v.trim()),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh, size: 18),
                tooltip: '刷新',
                visualDensity: VisualDensity.compact,
              ),
              IconButton(
                onPressed: _connections.isEmpty
                    ? null
                    : () async {
                        await _closeAllConnections();
                        _refresh();
                      },
                icon: const Icon(Icons.close_rounded, size: 18),
                tooltip: '关闭全部',
                visualDensity: VisualDensity.compact,
                color: Colors.red.shade300,
              ),
            ],
          ),
        ),

        // Connection list
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text(
                      _searchQuery.isEmpty ? '暂无活动连接' : '未找到匹配的连接',
                      style: Theme.of(context).textTheme.bodyMedium))
              : ListView.separated(
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final conn = filtered[index];
                    return _ConnectionTile(
                      conn: conn,
                      onTap: () => _showConnectionDetail(context, conn),
                      onClose: () async {
                        await _closeConnection(conn.id);
                        _refresh();
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showConnectionDetail(BuildContext context, ConnectionInfo conn) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    conn.network == 'udp' ? Icons.swap_horiz : Icons.link,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(conn.host,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const Divider(height: 24),
              _DetailRow(label: '协议', value: conn.network.toUpperCase()),
              _DetailRow(label: '规则', value: conn.rule),
              _DetailRow(label: '代理链', value: conn.chains),
              _DetailRow(label: '上传', value: formatBytes(conn.upload)),
              _DetailRow(label: '下载', value: formatBytes(conn.download)),
              _DetailRow(
                  label: '开始时间',
                  value:
                      '${conn.start.hour.toString().padLeft(2, '0')}:${conn.start.minute.toString().padLeft(2, '0')}:${conn.start.second.toString().padLeft(2, '0')}'),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await _closeConnection(conn.id);
                    _refresh();
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                  icon: const Icon(Icons.close, size: 16),
                  label: const Text('关闭连接'),
                  style:
                      OutlinedButton.styleFrom(foregroundColor: Colors.red),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ==================================================================
// Logs tab
// ==================================================================

class _LogsTab extends ConsumerStatefulWidget {
  const _LogsTab();

  @override
  ConsumerState<_LogsTab> createState() => _LogsTabState();
}

class _LogsTabState extends ConsumerState<_LogsTab> {
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final logs = ref.watch(logEntriesProvider);
    final level = ref.watch(logLevelProvider);

    final filtered = _filterLogs(logs);

    return Column(
      children: [
        // Controls
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: '搜索日志...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? GestureDetector(
                              onTap: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                              child: const Icon(Icons.clear, size: 16),
                            )
                          : null,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                    ),
                    style: const TextStyle(fontSize: 13),
                    onChanged: (v) =>
                        setState(() => _searchQuery = v.trim()),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              // Level filter
              PopupMenuButton<String>(
                initialValue: level,
                onSelected: (v) =>
                    ref.read(logLevelProvider.notifier).state = v,
                tooltip: '日志级别',
                icon: Icon(Icons.filter_list, size: 18,
                    color: level != 'info'
                        ? Theme.of(context).colorScheme.primary
                        : null),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'debug', child: Text('Debug')),
                  PopupMenuItem(value: 'info', child: Text('Info')),
                  PopupMenuItem(value: 'warning', child: Text('Warning')),
                  PopupMenuItem(value: 'error', child: Text('Error')),
                ],
              ),
              IconButton(
                onPressed: () =>
                    ref.read(logEntriesProvider.notifier).clear(),
                icon: const Icon(Icons.delete_outline, size: 18),
                tooltip: '清空日志',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),

        // Log entries
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: Text('暂无日志',
                      style: Theme.of(context).textTheme.bodyMedium))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    return _LogTile(entry: filtered[index]);
                  },
                ),
        ),

        // Entry count
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Row(
            children: [
              Text('${filtered.length} 条日志',
                  style: Theme.of(context).textTheme.bodySmall),
              const Spacer(),
              Text('级别: ${level.toUpperCase()}',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }

  List<LogEntry> _filterLogs(List<LogEntry> logs) {
    final level = ref.read(logLevelProvider);
    final levelOrder = {'debug': 0, 'info': 1, 'warning': 2, 'error': 3};
    final minLevel = levelOrder[level] ?? 1;

    var filtered = logs
        .where((l) => (levelOrder[l.type] ?? 1) >= minLevel)
        .toList();

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      filtered = filtered
          .where((l) => l.payload.toLowerCase().contains(q))
          .toList();
    }

    return filtered;
  }
}

class _LogTile extends StatelessWidget {
  final LogEntry entry;
  const _LogTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timestamp
          SizedBox(
            width: 60,
            child: Text(
              '${entry.timestamp.hour.toString().padLeft(2, '0')}:${entry.timestamp.minute.toString().padLeft(2, '0')}:${entry.timestamp.second.toString().padLeft(2, '0')}',
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          // Level badge
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 4, right: 6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _levelColor(entry.type),
            ),
          ),
          // Payload
          Expanded(
            child: SelectableText(
              entry.payload,
              style: TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
                height: 1.4,
                color: entry.type == 'error'
                    ? Colors.red
                    : entry.type == 'warning'
                        ? Colors.orange
                        : Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _levelColor(String type) {
    switch (type) {
      case 'error':
        return Colors.red;
      case 'warning':
        return Colors.orange;
      case 'debug':
        return Colors.grey;
      default:
        return Colors.green;
    }
  }
}

// ==================================================================
// Rules tab
// ==================================================================

class _RulesTab extends ConsumerStatefulWidget {
  const _RulesTab();

  @override
  ConsumerState<_RulesTab> createState() => _RulesTabState();
}

class _RulesTabState extends ConsumerState<_RulesTab> {
  String _searchQuery = '';
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(rulesProvider.notifier).refresh());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rules = ref.watch(rulesProvider);
    final filtered = _filterRules(rules);

    return Column(
      children: [
        // Summary
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          child: Row(
            children: [
              Icon(Icons.rule_folder_outlined,
                  size: 18, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 8),
              Text('共 ${rules.length} 条规则',
                  style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              if (_searchQuery.isNotEmpty)
                Text('匹配 ${filtered.length} 条',
                    style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        const Divider(height: 1),

        // Search
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: '搜索规则...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? GestureDetector(
                              onTap: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                              child: const Icon(Icons.clear, size: 16),
                            )
                          : null,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest,
                    ),
                    style: const TextStyle(fontSize: 13),
                    onChanged: (v) =>
                        setState(() => _searchQuery = v.trim()),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                onPressed: () =>
                    ref.read(rulesProvider.notifier).refresh(),
                icon: const Icon(Icons.refresh, size: 18),
                tooltip: '刷新',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),

        // Rules list
        Expanded(
          child: rules.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : filtered.isEmpty
                  ? Center(
                      child: Text('未找到匹配的规则',
                          style: Theme.of(context).textTheme.bodyMedium))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        return _RuleTile(rule: filtered[index]);
                      },
                    ),
        ),
      ],
    );
  }

  List<RuleInfo> _filterRules(List<RuleInfo> rules) {
    if (_searchQuery.isEmpty) return rules;
    final q = _searchQuery.toLowerCase();
    return rules
        .where((r) =>
            r.type.toLowerCase().contains(q) ||
            r.payload.toLowerCase().contains(q) ||
            r.proxy.toLowerCase().contains(q))
        .toList();
  }
}

class _RuleTile extends StatelessWidget {
  final RuleInfo rule;
  const _RuleTile({required this.rule});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          // Type badge
          Container(
            width: 96,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: _typeColor(context).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              rule.type,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: _typeColor(context),
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 8),
          // Payload
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rule.payload.isEmpty ? '*' : rule.payload,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  overflow: TextOverflow.ellipsis,
                ),
                if (rule.size > 0)
                  Text('${rule.size} 条',
                      style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(width: 6),
          // Proxy target
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              rule.proxy,
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).colorScheme.onSecondaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _typeColor(BuildContext context) {
    switch (rule.type) {
      case 'DOMAIN-SUFFIX':
      case 'DOMAIN':
        return Colors.blue;
      case 'DOMAIN-KEYWORD':
        return Colors.teal;
      case 'GEOIP':
        return Colors.orange;
      case 'RULE-SET':
        return Colors.purple;
      case 'MATCH':
        return Colors.red;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }
}

// ==================================================================
// Shared widgets
// ==================================================================

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(value,
                style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

class _ConnectionTile extends StatelessWidget {
  final ConnectionInfo conn;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const _ConnectionTile({
    required this.conn,
    required this.onTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      onTap: onTap,
      leading: Icon(
        conn.network == 'udp' ? Icons.swap_horiz : Icons.link,
        size: 18,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text(conn.host, style: const TextStyle(fontSize: 13)),
      subtitle: Text(
        '${conn.network.toUpperCase()} · ${conn.rule} · ${conn.chains}',
        style: const TextStyle(fontSize: 11),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.close, size: 16),
        onPressed: onClose,
        visualDensity: VisualDensity.compact,
        color: Colors.red.shade300,
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  const _StatChip({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: iconColor),
            const SizedBox(width: 4),
            Text(value,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
