/// Unified traffic/speed formatter used across Dashboard, Nodes, and Connections.
///
/// Two variants:
///   [TrafficFormatter.speed] — bytes/second → "1.2 MB/s"
///   [TrafficFormatter.bytes] — total bytes   → "1.2 MB"
class TrafficFormatter {
  TrafficFormatter._();

  /// Format a bytes-per-second value with auto unit scaling.
  ///
  /// Examples: 512 → "512 B/s", 1536 → "1.5 KB/s", 2097152 → "2.0 MB/s"
  static String speed(int bps) {
    if (bps < 1024) return '$bps B/s';
    if (bps < 1024 * 1024) {
      return '${(bps / 1024).toStringAsFixed(1)} KB/s';
    }
    if (bps < 1024 * 1024 * 1024) {
      return '${(bps / (1024 * 1024)).toStringAsFixed(1)} MB/s';
    }
    return '${(bps / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB/s';
  }

  /// Format a total byte count with auto unit scaling (no "/s").
  ///
  /// Examples: 512 → "512 B", 1536 → "1.5 KB", 2097152 → "2.0 MB"
  static String bytes(int b) {
    if (b < 1024) return '$b B';
    if (b < 1024 * 1024) {
      return '${(b / 1024).toStringAsFixed(1)} KB';
    }
    if (b < 1024 * 1024 * 1024) {
      return '${(b / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
