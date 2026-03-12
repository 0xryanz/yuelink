/// Traffic rate snapshot.
class Traffic {
  final int up; // bytes per second
  final int down; // bytes per second

  const Traffic({this.up = 0, this.down = 0});

  String get upFormatted => _formatBytes(up);
  String get downFormatted => _formatBytes(down);
}

/// Connection info.
class ConnectionInfo {
  final String id;
  final String host;
  final String network; // tcp, udp
  final String type;
  final String rule;
  final String chains; // proxy chain
  final int upload;
  final int download;
  final DateTime start;

  const ConnectionInfo({
    required this.id,
    required this.host,
    required this.network,
    required this.type,
    required this.rule,
    required this.chains,
    required this.upload,
    required this.download,
    required this.start,
  });

  factory ConnectionInfo.fromJson(Map<String, dynamic> json) {
    final meta = json['metadata'] as Map<String, dynamic>? ?? {};
    return ConnectionInfo(
      id: json['id'] as String? ?? '',
      host: '${meta['host'] ?? meta['destinationIP'] ?? ''}:${meta['destinationPort'] ?? ''}',
      network: meta['network'] as String? ?? '',
      type: meta['type'] as String? ?? '',
      rule: '${json['rule'] ?? ''}${json['rulePayload'] != null ? ' (${json['rulePayload']})' : ''}',
      chains: (json['chains'] as List?)?.join(' → ') ?? '',
      upload: json['upload'] as int? ?? 0,
      download: json['download'] as int? ?? 0,
      start: DateTime.tryParse(json['start'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

/// Format bytes to human-readable string.
String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B/s';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB/s';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB/s';
}
