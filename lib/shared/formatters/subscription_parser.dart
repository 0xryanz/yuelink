/// Parses subscription response headers and content.
///
/// Clash/mihomo subscriptions return useful metadata in HTTP headers:
/// - `subscription-userinfo`: traffic quota and expiry
/// - `content-disposition`: suggested filename
/// - `profile-update-interval`: update frequency in hours
class SubscriptionInfo {
  final int? upload; // bytes used upload
  final int? download; // bytes used download
  final int? total; // total quota bytes
  final DateTime? expire; // expiry date
  final int? updateInterval; // hours

  const SubscriptionInfo({
    this.upload,
    this.download,
    this.total,
    this.expire,
    this.updateInterval,
  });

  /// Remaining traffic in bytes, or null if unknown.
  int? get remaining {
    if (total == null) return null;
    return total! - (upload ?? 0) - (download ?? 0);
  }

  /// Usage percentage (0.0 - 1.0), or null if unknown.
  double? get usagePercent {
    if (total == null || total == 0) return null;
    final used = (upload ?? 0) + (download ?? 0);
    return used / total!;
  }

  /// Whether the subscription has expired.
  bool get isExpired {
    if (expire == null) return false;
    return DateTime.now().isAfter(expire!);
  }

  /// Days until expiry, or null if unknown.
  int? get daysRemaining {
    if (expire == null) return null;
    return expire!.difference(DateTime.now()).inDays;
  }

  /// Parse from HTTP response headers.
  ///
  /// Expects the `subscription-userinfo` header format:
  /// `upload=1234; download=5678; total=10000000000; expire=1700000000`
  factory SubscriptionInfo.fromHeaders(Map<String, String> headers) {
    final userInfo = headers['subscription-userinfo'] ?? '';
    final interval = headers['profile-update-interval'];

    int? upload, download, total;
    DateTime? expire;

    for (final part in userInfo.split(';')) {
      final kv = part.trim().split('=');
      if (kv.length != 2) continue;
      final key = kv[0].trim().toLowerCase();
      final value = int.tryParse(kv[1].trim());
      if (value == null) continue;

      switch (key) {
        case 'upload':
          upload = value;
        case 'download':
          download = value;
        case 'total':
          total = value;
        case 'expire':
          expire = DateTime.fromMillisecondsSinceEpoch(value * 1000);
      }
    }

    return SubscriptionInfo(
      upload: upload,
      download: download,
      total: total,
      expire: expire,
      updateInterval: interval != null ? int.tryParse(interval) : null,
    );
  }

  Map<String, dynamic> toJson() => {
        if (upload != null) 'upload': upload,
        if (download != null) 'download': download,
        if (total != null) 'total': total,
        if (expire != null) 'expire': expire!.millisecondsSinceEpoch ~/ 1000,
        if (updateInterval != null) 'updateInterval': updateInterval,
      };

  factory SubscriptionInfo.fromJson(Map<String, dynamic> json) {
    return SubscriptionInfo(
      upload: json['upload'] as int?,
      download: json['download'] as int?,
      total: json['total'] as int?,
      expire: json['expire'] != null
          ? DateTime.fromMillisecondsSinceEpoch(
              (json['expire'] as int) * 1000)
          : null,
      updateInterval: json['updateInterval'] as int?,
    );
  }
}

/// Format bytes to human-readable string (e.g. "1.5 GB").
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes < 1024 * 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  return '${(bytes / (1024 * 1024 * 1024 * 1024)).toStringAsFixed(1)} TB';
}
