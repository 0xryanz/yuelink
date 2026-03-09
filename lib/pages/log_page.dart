import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/core_controller.dart';
import '../models/traffic.dart';
import '../providers/core_provider.dart';

class LogPage extends ConsumerStatefulWidget {
  const LogPage({super.key});

  @override
  ConsumerState<LogPage> createState() => _LogPageState();
}

class _LogPageState extends ConsumerState<LogPage> {
  List<ConnectionInfo> _connections = [];
  int _uploadTotal = 0;
  int _downloadTotal = 0;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) _refresh();
    });
  }

  void _stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  void _refresh() {
    final data = CoreController.instance.getConnections();
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

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(coreStatusProvider);
    final isRunning = status == CoreStatus.running;

    // Auto-refresh when running
    if (isRunning && _refreshTimer == null) {
      _startAutoRefresh();
    } else if (!isRunning && _refreshTimer != null) {
      _stopAutoRefresh();
    }

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
              Text('请先连接以查看连接日志',
                  style: Theme.of(context).textTheme.bodyLarge),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: Column(
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
                  value: _formatTotal(_uploadTotal),
                ),
                _StatChip(
                  icon: Icons.arrow_downward,
                  iconColor: Colors.green,
                  label: '总下载',
                  value: _formatTotal(_downloadTotal),
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

          // Action bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: _refresh,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('刷新'),
                ),
                const Spacer(),
                TextButton.icon(
                  onPressed: _connections.isEmpty
                      ? null
                      : () {
                          CoreController.instance.closeAllConnections();
                          _refresh();
                        },
                  icon: const Icon(Icons.close_rounded, size: 16),
                  label: const Text('关闭全部'),
                  style: TextButton.styleFrom(foregroundColor: Colors.red),
                ),
              ],
            ),
          ),

          // Connection list
          Expanded(
            child: _connections.isEmpty
                ? Center(
                    child: Text('暂无活动连接',
                        style: Theme.of(context).textTheme.bodyMedium))
                : ListView.separated(
                    itemCount: _connections.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final conn = _connections[index];
                      return _ConnectionTile(
                        conn: conn,
                        onClose: () {
                          CoreController.instance.closeConnection(conn.id);
                          _refresh();
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _formatTotal(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

class _ConnectionTile extends StatelessWidget {
  final ConnectionInfo conn;
  final VoidCallback onClose;

  const _ConnectionTile({required this.conn, required this.onClose});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
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
