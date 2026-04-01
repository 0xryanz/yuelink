import 'dart:async';

import 'package:flutter/material.dart';

import '../../theme.dart';
import 'status_models.dart';
import 'status_repository.dart';

/// 网络状态原生页面 — 替代 WebView 版 status.yue.to。
class StatusPage extends StatefulWidget {
  const StatusPage({super.key});

  @override
  State<StatusPage> createState() => _StatusPageState();
}

class _StatusPageState extends State<StatusPage> {
  final _repo = StatusRepository();
  StatusData? _data;
  bool _loading = true;
  String? _error;
  Timer? _autoRefresh;

  @override
  void initState() {
    super.initState();
    _fetch();
    _autoRefresh = Timer.periodic(const Duration(seconds: 60), (_) => _fetch());
  }

  @override
  void dispose() {
    _autoRefresh?.cancel();
    super.dispose();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _repo.fetch();
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '网络请求失败，请稍后重试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        leading: const BackButton(),
        title: const Text('网络状态'),
        backgroundColor: isDark ? YLColors.zinc900 : Colors.white,
        foregroundColor: isDark ? Colors.white : YLColors.zinc900,
        elevation: 0,
      ),
      backgroundColor: isDark ? YLColors.zinc950 : YLColors.zinc50,
      body: RefreshIndicator(
        onRefresh: _fetch,
        child: _buildBody(isDark),
      ),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_loading && _data == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null && _data == null) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Icon(Icons.cloud_off_outlined, size: 40, color: YLColors.zinc400),
          const SizedBox(height: 12),
          Text(
            _error!,
            style: YLText.body.copyWith(color: YLColors.zinc500),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Center(
            child: TextButton.icon(
              onPressed: _fetch,
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('重试'),
            ),
          ),
        ],
      );
    }

    final data = _data!;
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        _SummaryCard(data: data, isDark: isDark),
        const SizedBox(height: 16),
        _SectionTitle('区域状态', isDark: isDark),
        const SizedBox(height: 8),
        ...data.regions.map((r) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _RegionTile(region: r, isDark: isDark),
            )),
        const SizedBox(height: 16),
        _SectionTitle('最近事件', isDark: isDark),
        const SizedBox(height: 8),
        if (data.incidents.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline, size: 16, color: YLColors.connected),
                const SizedBox(width: 6),
                Text(
                  '近 30 天无故障事件',
                  style: YLText.caption.copyWith(color: YLColors.zinc500),
                ),
              ],
            ),
          )
        else
          ...data.incidents.map((i) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _IncidentTile(incident: i, isDark: isDark),
              )),
        const SizedBox(height: 12),
        Text(
          '更新于 ${_formatTime(data.updatedAt)}',
          style: YLText.caption.copyWith(color: YLColors.zinc400),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
      ],
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

// ── 总体状态卡 ────────────────────────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final StatusData data;
  final bool isDark;
  const _SummaryCard({required this.data, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final status = data.overallStatus;
    final Color statusColor;
    final IconData statusIcon;
    final String statusText;

    switch (status) {
      case 'operational':
        statusColor = YLColors.connected;
        statusIcon = Icons.check_circle_rounded;
        statusText = '所有服务运行正常';
      case 'degraded':
        statusColor = YLColors.connecting;
        statusIcon = Icons.warning_rounded;
        statusText = '部分区域服务波动';
      default:
        statusColor = YLColors.error;
        statusIcon = Icons.error_rounded;
        statusText = '部分区域服务中断';
    }

    return Container(
      padding: const EdgeInsets.all(20),
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
        children: [
          Icon(statusIcon, color: statusColor, size: 36),
          const SizedBox(height: 10),
          Text(
            statusText,
            style: YLText.titleMedium.copyWith(
              color: isDark ? Colors.white : YLColors.zinc900,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _StatPill(
                label: '区域',
                value: '${data.totalRegions}',
                isDark: isDark,
              ),
              _StatPill(
                label: '正常',
                value: '${data.healthyRegions}',
                isDark: isDark,
                valueColor: YLColors.connected,
              ),
              if (data.downRegions > 0)
                _StatPill(
                  label: '异常',
                  value: '${data.downRegions}',
                  isDark: isDark,
                  valueColor: YLColors.error,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final String value;
  final bool isDark;
  final Color? valueColor;
  const _StatPill({required this.label, required this.value, required this.isDark, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: YLText.titleLarge.copyWith(
            color: valueColor ?? (isDark ? Colors.white : YLColors.zinc900),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: YLText.caption.copyWith(color: YLColors.zinc500)),
      ],
    );
  }
}

// ── 区域行 ──────────────────────────────────────────────────────────────────

class _RegionTile extends StatelessWidget {
  final StatusRegion region;
  final bool isDark;
  const _RegionTile({required this.region, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final Color dotColor;
    switch (region.statusLevel) {
      case 'excellent':
      case 'good':
        dotColor = YLColors.connected;
      case 'degraded':
        dotColor = YLColors.connecting;
      default:
        dotColor = YLColors.error;
    }

    final availText = region.availability24h != null
        ? '${region.availability24h!.toStringAsFixed(1)}%'
        : '--';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? YLColors.zinc800 : Colors.white,
        borderRadius: BorderRadius.circular(YLRadius.lg),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.06),
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          // Flag + name
          Text(region.flag, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  region.regionName,
                  style: YLText.label.copyWith(
                    color: isDark ? Colors.white : YLColors.zinc900,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${region.onlineServers}/${region.totalServers} 在线',
                  style: YLText.caption.copyWith(color: YLColors.zinc500),
                ),
              ],
            ),
          ),
          // Availability
          Text(
            availText,
            style: YLText.label.copyWith(
              color: isDark ? YLColors.zinc300 : YLColors.zinc600,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 10),
          // Status dot
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: dotColor,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
    );
  }
}

// ── 事件行 ──────────────────────────────────────────────────────────────────

class _IncidentTile extends StatelessWidget {
  final StatusIncident incident;
  final bool isDark;
  const _IncidentTile({required this.incident, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final isResolved = incident.isResolved;
    final Color accentColor = isResolved ? YLColors.connected : YLColors.connecting;
    final String statusText;
    switch (incident.status) {
      case 'resolved':
        statusText = '已恢复';
      case 'investigating':
        statusText = '排查中';
      case 'monitoring':
        statusText = '监控中';
      default:
        statusText = incident.status;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? YLColors.zinc800 : Colors.white,
        borderRadius: BorderRadius.circular(YLRadius.lg),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.06)
              : Colors.black.withValues(alpha: 0.06),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(YLRadius.sm),
                ),
                child: Text(
                  statusText,
                  style: YLText.caption.copyWith(
                    color: accentColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  incident.scopeName,
                  style: YLText.caption.copyWith(color: YLColors.zinc500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            incident.title,
            style: YLText.label.copyWith(
              color: isDark ? Colors.white : YLColors.zinc900,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (incident.summary != null && incident.summary!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              incident.summary!,
              style: YLText.caption.copyWith(color: YLColors.zinc500),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 6),
          Text(
            _timeRange(incident),
            style: YLText.caption.copyWith(color: YLColors.zinc400, fontSize: 11),
          ),
        ],
      ),
    );
  }

  String _timeRange(StatusIncident i) {
    final start = _fmt(i.startedAt);
    final end = i.resolvedAt != null ? _fmt(i.resolvedAt) : '进行中';
    return '$start → $end';
  }

  String _fmt(String? iso) {
    if (iso == null) return '';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}

// ── Section title ───────────────────────────────────────────────────────────

class _SectionTitle extends StatelessWidget {
  final String text;
  final bool isDark;
  const _SectionTitle(this.text, {required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: YLText.label.copyWith(
        color: isDark ? YLColors.zinc300 : YLColors.zinc600,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
