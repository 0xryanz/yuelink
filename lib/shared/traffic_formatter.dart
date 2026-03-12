/// Unified traffic/speed formatter used across Dashboard, Nodes, and Connections.
///
/// Two variants:
///   [TrafficFormatter.speed] — bytes/second → "1.2 MB/s"
///   [TrafficFormatter.bytes] — total bytes   → "1.2 MB"
class TrafficFormatter {
  TrafficFormatter._();

  /// Format a bytes-per-second value. Always shows MB or GB (no /s suffix).
  ///
  /// Examples: 512 → "0.00 MB", 1536 → "0.00 MB", 2097152 → "2.00 MB"
  static String speed(int bps) {
    if (bps < 1024 * 1024 * 1024) {
      return '${(bps / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bps / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Format a total byte count. Always shows MB or GB.
  ///
  /// Examples: 512 → "0.00 MB", 10485760 → "10.00 MB"
  static String bytes(int b) {
    if (b < 1024 * 1024 * 1024) {
      return '${(b / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
