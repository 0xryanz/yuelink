import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/storage/settings_service.dart';
import 'feature_flags.dart';
import 'telemetry.dart';

/// Net Promoter Score collection.
///
/// 2026 mainstream pattern: show a one-click survey anchored to a meaningful
/// moment, never mid-action, optional comment, and never re-prompt sooner
/// than 90 days after a dismiss.
///
/// Trigger — all must hold:
///   1. Telemetry opted in.
///   2. `nps_enabled` feature flag true.
///   3. First successful connect was ≥ 24h ago.
///   4. User has not already submitted.
///   5. If previously dismissed, 90+ days have passed.
class NpsService {
  NpsService._();

  static const _minSinceFirstConnect = Duration(hours: 24);
  static const _redisplayAfterDismiss = Duration(days: 90);
  static const _endpoint =
      'https://yue.yuebao.website/api/client/telemetry/nps';

  static const _kFirstConnect = 'firstConnectTs';
  static const _kLastPrompt = 'npsLastPromptTs';
  static const _kSubmitted = 'npsSubmitted';

  /// Mark the first-ever successful connect. Idempotent — first call wins.
  static Future<void> markFirstConnect() async {
    final existing = await SettingsService.get<int>(_kFirstConnect);
    if (existing != null) return;
    await SettingsService.set(
      _kFirstConnect,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Check whether the survey should be shown. Cheap (3 disk reads).
  static Future<bool> shouldShow() async {
    if (!Telemetry.isEnabled) return false;
    if (!FeatureFlags.I.boolFlag('nps_enabled')) return false;

    final submitted =
        (await SettingsService.get<bool>(_kSubmitted)) ?? false;
    if (submitted) return false;

    final firstConnect = await SettingsService.get<int>(_kFirstConnect);
    if (firstConnect == null) return false;
    final since = DateTime.now().difference(
      DateTime.fromMillisecondsSinceEpoch(firstConnect),
    );
    if (since < _minSinceFirstConnect) return false;

    final lastPrompt = await SettingsService.get<int>(_kLastPrompt);
    if (lastPrompt != null) {
      final sinceLast = DateTime.now().difference(
        DateTime.fromMillisecondsSinceEpoch(lastPrompt),
      );
      if (sinceLast < _redisplayAfterDismiss) return false;
    }
    return true;
  }

  static Future<void> recordShown() async {
    await SettingsService.set(
      _kLastPrompt,
      DateTime.now().millisecondsSinceEpoch,
    );
    Telemetry.event('nps_shown');
  }

  static Future<void> submit({required int score, String? comment}) async {
    final clamped = score.clamp(0, 10);
    final trimmed = (comment ?? '').trim();
    final safeComment =
        trimmed.length > 500 ? trimmed.substring(0, 500) : trimmed;

    await SettingsService.set(_kSubmitted, true);

    Telemetry.event('nps_submit', props: {
      'score': clamped,
      'has_comment': safeComment.isNotEmpty,
    });

    // Direct POST so comments never land in the generic telemetry ring.
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    String version = '';
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version;
    } catch (_) {}
    try {
      final req = await client.postUrl(Uri.parse(_endpoint));
      req.headers.set('Content-Type', 'application/json');
      req.write(jsonEncode({
        'client_id': Telemetry.clientId,
        'platform': _platformName(),
        'version': version,
        'score': clamped,
        'comment': safeComment,
        'ts': DateTime.now().millisecondsSinceEpoch,
      }));
      await req.close().timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('[NPS] submit failed: $e');
    } finally {
      client.close();
    }
  }

  static void recordDismiss() {
    Telemetry.event('nps_dismiss');
  }

  static String _platformName() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    if (Platform.isLinux) return 'linux';
    return 'unknown';
  }
}
