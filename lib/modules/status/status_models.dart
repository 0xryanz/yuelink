/// 网络状态页数据模型（对应 /api/status/nodes + /api/status/incidents）。

class StatusRegion {
  final String region;
  final String regionName;
  final String flag;
  final String statusLevel;
  final double? availability24h;
  final int onlineServers;
  final int totalServers;

  const StatusRegion({
    required this.region,
    required this.regionName,
    required this.flag,
    required this.statusLevel,
    this.availability24h,
    required this.onlineServers,
    required this.totalServers,
  });

  // ISO 3166-1 alpha-2 修正：后端存 "UK" 但标准代码是 "GB"
  static const _flagFix = {'UK': '🇬🇧'};

  factory StatusRegion.fromJson(Map<String, dynamic> j) {
    final code = (j['region'] as String? ?? '').toUpperCase();
    final flag = _flagFix[code] ?? (j['flag'] as String? ?? '');
    return StatusRegion(
        region: code,
        regionName: j['region_name'] as String? ?? '',
        flag: flag,
        statusLevel: j['status_level'] as String? ?? 'down',
        availability24h: (j['availability_24h'] as num?)?.toDouble(),
        onlineServers: (j['online_servers'] as num?)?.toInt() ?? 0,
        totalServers: (j['total_servers'] as num?)?.toInt() ?? 0,
      );
  }

  bool get isAllOnline => onlineServers == totalServers && totalServers > 0;
}

class StatusIncident {
  final int id;
  final String title;
  final String scopeName;
  final String status;
  final String impactLevel;
  final String? startedAt;
  final String? resolvedAt;
  final String? summary;

  const StatusIncident({
    required this.id,
    required this.title,
    required this.scopeName,
    required this.status,
    required this.impactLevel,
    this.startedAt,
    this.resolvedAt,
    this.summary,
  });

  factory StatusIncident.fromJson(Map<String, dynamic> j) => StatusIncident(
        id: (j['id'] as num?)?.toInt() ?? 0,
        title: j['title'] as String? ?? '',
        scopeName: j['scope_name'] as String? ?? '',
        status: j['status'] as String? ?? '',
        impactLevel: j['impact_level'] as String? ?? 'minor',
        startedAt: j['started_at'] as String?,
        resolvedAt: j['resolved_at'] as String?,
        summary: j['summary'] as String?,
      );

  bool get isResolved => status == 'resolved';
}

class StatusData {
  final List<StatusRegion> regions;
  final List<StatusIncident> incidents;
  final String updatedAt;

  const StatusData({
    required this.regions,
    required this.incidents,
    required this.updatedAt,
  });

  int get totalRegions => regions.length;
  int get healthyRegions => regions.where((r) => r.statusLevel == 'excellent' || r.statusLevel == 'good').length;
  int get degradedRegions => regions.where((r) => r.statusLevel == 'degraded').length;
  int get downRegions => regions.where((r) => r.statusLevel == 'down').length;

  String get overallStatus {
    if (downRegions > 0) return 'down';
    if (degradedRegions > 0) return 'degraded';
    return 'operational';
  }
}
