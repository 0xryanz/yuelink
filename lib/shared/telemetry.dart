import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/storage/settings_service.dart';

/// Anonymous, opt-in telemetry for understanding feature usage.
///
/// Privacy: NO PII (email, token, subscription URL, node info).
/// Events are batched in-memory and flushed every 60s or on app pause.
/// Can be disabled in Settings → Privacy.
///
/// Events sent: { event, platform, appVersion, timestamp }
class Telemetry {
  static const _endpoint = 'https://yue.yuebao.website/api/client/telemetry';
  static const _flushInterval = Duration(seconds: 60);
  static const _maxBatch = 50;

  static final List<Map<String, dynamic>> _buffer = [];
  static Timer? _flushTimer;
  static bool _enabled = false;
  static String _platform = '';
  static String _version = '';

  /// Call once at app startup.
  static Future<void> init() async {
    _enabled = await SettingsService.getTelemetryEnabled();
    if (Platform.isAndroid) {
      _platform = 'android';
    } else if (Platform.isIOS) {
      _platform = 'ios';
    } else if (Platform.isMacOS) {
      _platform = 'macos';
    } else if (Platform.isWindows) {
      _platform = 'windows';
    } else if (Platform.isLinux) {
      _platform = 'linux';
    }
    try {
      final info = await PackageInfo.fromPlatform();
      _version = info.version;
    } catch (_) {}
    if (_enabled) _startTimer();
  }

  static void setEnabled(bool enabled) {
    _enabled = enabled;
    SettingsService.setTelemetryEnabled(enabled);
    if (enabled) {
      _startTimer();
    } else {
      _flushTimer?.cancel();
      _buffer.clear();
    }
  }

  static bool get isEnabled => _enabled;

  /// Record an event. Call from feature entry points.
  /// Example: Telemetry.event('login_success') / Telemetry.event('qr_scan_import')
  static void event(String name, [Map<String, dynamic>? props]) {
    if (!_enabled) return;
    if (_buffer.length >= _maxBatch) return; // overflow protection
    _buffer.add({
      'event': name,
      'platform': _platform,
      'version': _version,
      'ts': DateTime.now().millisecondsSinceEpoch,
      if (props != null) ...props,
    });
  }

  static void _startTimer() {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(_flushInterval, (_) => flush());
  }

  /// Flush buffered events to server. Fire-and-forget.
  static Future<void> flush() async {
    if (_buffer.isEmpty) return;
    final events = List<Map<String, dynamic>>.from(_buffer);
    _buffer.clear();
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    try {
      final req = await client.postUrl(Uri.parse(_endpoint));
      req.headers.set('Content-Type', 'application/json');
      req.write(jsonEncode({'events': events}));
      await req.close().timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('[Telemetry] flush failed: $e');
    } finally {
      client.close();
    }
  }
}
