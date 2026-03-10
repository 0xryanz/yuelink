import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

/// Real-time WebSocket streaming from mihomo external-controller.
///
/// mihomo exposes these WebSocket endpoints:
/// - /traffic — upload/download bytes per second
/// - /logs — log entries with type and payload
/// - /connections — live connection snapshots
/// - /memory — memory usage (inuse bytes)
class MihomoStream {
  MihomoStream({
    this.host = '127.0.0.1',
    this.port = 9090,
    this.secret,
  });

  final String host;
  final int port;
  final String? secret;

  String get _wsBase => 'ws://$host:$port';

  // ------------------------------------------------------------------
  // Traffic stream
  // ------------------------------------------------------------------

  /// Stream of traffic snapshots: {up: int, down: int} bytes/sec.
  Stream<({int up, int down})> trafficStream() {
    return _connect('/traffic').map((data) {
      return (
        up: (data['up'] as num?)?.toInt() ?? 0,
        down: (data['down'] as num?)?.toInt() ?? 0,
      );
    });
  }

  // ------------------------------------------------------------------
  // Log stream
  // ------------------------------------------------------------------

  /// Stream of log entries: {type: String, payload: String}.
  Stream<LogEntry> logStream({String level = 'info'}) {
    return _connect('/logs?level=$level').map((data) {
      return LogEntry(
        type: data['type'] as String? ?? 'info',
        payload: data['payload'] as String? ?? '',
      );
    });
  }

  // ------------------------------------------------------------------
  // Memory stream
  // ------------------------------------------------------------------

  /// Stream of memory usage in bytes.
  Stream<int> memoryStream() {
    return _connect('/memory').map((data) {
      return (data['inuse'] as num?)?.toInt() ?? 0;
    });
  }

  // ------------------------------------------------------------------
  // Connections stream
  // ------------------------------------------------------------------

  /// Stream of full connection snapshots.
  Stream<Map<String, dynamic>> connectionsStream() {
    return _connect('/connections');
  }

  // ------------------------------------------------------------------
  // Internal
  // ------------------------------------------------------------------

  Stream<Map<String, dynamic>> _connect(String path) {
    // Use token query param for auth (mihomo supports both header and query).
    final separator = path.contains('?') ? '&' : '?';
    final authPath = secret != null ? '$path${separator}token=$secret' : path;
    final uri = Uri.parse('$_wsBase$authPath');

    final channel = WebSocketChannel.connect(uri);

    return channel.stream
        .map((event) => json.decode(event as String) as Map<String, dynamic>)
        .handleError((_) {
      // Connection closed or error — stream ends
    });
  }
}

/// A single log entry from mihomo.
class LogEntry {
  final String type; // info, warning, error, debug
  final String payload;
  final DateTime timestamp;

  LogEntry({
    required this.type,
    required this.payload,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}
