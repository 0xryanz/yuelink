import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../storage/settings_service.dart';

/// Callback type for VPN revocation events.

/// Platform-specific VPN service abstraction.
///
/// Handles starting/stopping the OS-level VPN tunnel:
/// - Android: VpnService → returns TUN fd for injection into config YAML
/// - iOS: NEPacketTunnelProvider (Go core runs inside the extension)
/// - macOS: system proxy via networksetup
/// - Windows: system proxy via registry
class VpnService {
  static const _channel = MethodChannel('com.yueto.yuelink/vpn');

  /// Start the Android VPN service and obtain the TUN file descriptor.
  ///
  /// Returns the fd integer (> 0) on success, or -1 on failure.
  /// The fd must be injected into the mihomo config YAML as `tun.file-descriptor`
  /// before calling [CoreManager.start].
  ///
  /// Auto-retries once on first-attempt failure. Android's `establish()` can
  /// return null even after a fresh `RESULT_OK` from the permission dialog on
  /// Samsung / Xiaomi / Huawei ROMs — the system hasn't finished settling
  /// VPN state. 1.5 s later, it succeeds. Previously this manifested as
  /// "first connect fails, second connect works" — the same symptom class
  /// that bites Windows TUN cold start.
  static Future<int> startAndroidVpn({int mixedPort = 7890}) async {
    assert(Platform.isAndroid);
    final splitMode = await SettingsService.getSplitTunnelMode();
    final splitApps = await SettingsService.getSplitTunnelApps();

    Future<int> attempt() async {
      try {
        final fd = await _channel.invokeMethod<int>('startVpn', {
          'mixedPort': mixedPort,
          'splitMode': splitMode,
          'splitApps': splitApps,
        });
        return fd ?? -1;
      } on PlatformException catch (_) {
        return -1;
      }
    }

    var fd = await attempt();
    if (fd > 0) return fd;

    debugPrint('[VpnService] startAndroidVpn attempt-1 returned $fd — '
        'retrying once after 1.5 s (OEM settle race)');
    await Future.delayed(const Duration(milliseconds: 1500));
    fd = await attempt();
    if (fd <= 0) {
      debugPrint('[VpnService] startAndroidVpn retry also failed ($fd)');
    }
    return fd;
  }

  static const _appsChannel = MethodChannel('com.yueto.yuelink/apps');

  /// Returns installed apps as a list of {packageName, appName} maps.
  static Future<List<Map<String, String>>> getInstalledApps({
    bool showSystem = false,
  }) async {
    if (!Platform.isAndroid) return [];
    try {
      final raw = await _appsChannel.invokeListMethod<Map>(
        'getInstalledApps',
        {'showSystem': showSystem},
      );
      return (raw ?? [])
          .map((m) => {
                'packageName': m['packageName'] as String? ?? '',
                'appName': m['appName'] as String? ?? '',
              })
          .toList();
    } on PlatformException catch (e) {
      debugPrint('[VpnService] getInstalledApps PlatformException: $e');
      return [];
    } catch (e) {
      debugPrint('[VpnService] getInstalledApps error: $e');
      return [];
    }
  }

  /// Get the current TUN fd without starting a new tunnel.
  /// Returns -1 if the VPN is not running.
  static Future<int> getTunFd() async {
    assert(Platform.isAndroid);
    try {
      final fd = await _channel.invokeMethod<int>('getTunFd');
      return fd ?? -1;
    } on PlatformException catch (_) {
      return -1;
    }
  }

  /// Start the iOS VPN tunnel.
  ///
  /// [configYaml] is written to the App Group container so the
  /// PacketTunnel extension can load it on startup.
  static Future<bool> startIosVpn({required String configYaml}) async {
    assert(Platform.isIOS);
    // Do NOT catch PlatformException here — let it propagate so _step
    // records the actual iOS error code (VPN_SAVE_ERROR, VPN_START_ERROR, etc.)
    // in the startup report instead of the opaque "returned false" message.
    final result = await _channel.invokeMethod<bool>('startVpn', configYaml);
    return result ?? false;
  }

  /// Start the platform VPN tunnel (iOS / generic path).
  static Future<bool> startVpn() async {
    try {
      final result = await _channel.invokeMethod<bool>('startVpn');
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Stop the platform VPN tunnel.
  static Future<bool> stopVpn() async {
    try {
      final result = await _channel.invokeMethod<bool>('stopVpn');
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Request VPN permission (Android only).
  static Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final result = await _channel.invokeMethod<bool>('requestPermission');
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Set system proxy (desktop fallback mode).
  static Future<bool> setSystemProxy({
    required String host,
    required int httpPort,
    required int socksPort,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('setSystemProxy', {
        'host': host,
        'httpPort': httpPort,
        'socksPort': socksPort,
      });
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Clear system proxy settings.
  static Future<bool> clearSystemProxy() async {
    try {
      final result = await _channel.invokeMethod<bool>('clearSystemProxy');
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Remove all VPN profiles and reset state (iOS).
  /// Next startVpn will create a fresh profile and re-trigger the system prompt.
  static Future<bool> resetVpnProfile() async {
    if (!Platform.isIOS) return true; // Only needed on iOS
    try {
      final result = await _channel.invokeMethod<bool>('resetVpnProfile');
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Delete all config/geo files from the App Group container (iOS).
  /// Forces a full config rebuild on next connection.
  static Future<bool> clearAppGroupConfig() async {
    if (!Platform.isIOS) return true;
    try {
      final result = await _channel.invokeMethod<bool>('clearAppGroupConfig');
      return result ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Register callbacks for VPN lifecycle events (Android-focused).
  ///
  /// [onRevoked] fires when the system or another app revokes VPN permission.
  /// [onTransportChanged] fires when the underlying physical network flips
  /// (e.g. Wi-Fi dropped → cellular picked up on elevator entry); consumer
  /// should flush fake-ip cache + close stale connections + optionally
  /// re-test node latency for the new network.
  ///
  /// Call this once during app initialization. iOS does not emit
  /// `transportChanged` — Apple's NetworkExtension handles re-routing
  /// transparently and connections usually survive the switch.
  static void listenForRevocation(
    VoidCallback onRevoked, {
    void Function(String prev, String now)? onTransportChanged,
  }) {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'vpnRevoked':
          debugPrint('[VpnService] VPN revoked by system');
          onRevoked();
          break;
        case 'transportChanged':
          final args = (call.arguments as Map?)?.cast<String, dynamic>();
          final prev = args?['prev'] as String? ?? 'unknown';
          final now = args?['now'] as String? ?? 'unknown';
          debugPrint('[VpnService] transport changed: $prev → $now');
          onTransportChanged?.call(prev, now);
          break;
      }
    });
  }

  /// Whether the user has whitelisted YueLink from battery optimizations.
  /// Pre-M devices return true (no Doze). iOS / desktop always return true
  /// (not applicable).
  static Future<bool> isBatteryOptimizationIgnored() async {
    if (!Platform.isAndroid) return true;
    try {
      final ok = await _channel
          .invokeMethod<bool>('isBatteryOptimizationIgnored');
      return ok ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }

  /// Surface the system battery-optimization whitelist dialog (Android only).
  /// Returns false if the OS has no settings UI for it (rare; very old ROMs).
  ///
  /// Users on Xiaomi/Huawei/OPPO need this — Doze kills VpnService after
  /// screen-off + ~30 min idle. Whitelisted apps keep the tunnel alive.
  static Future<bool> requestIgnoreBatteryOptimization() async {
    if (!Platform.isAndroid) return true;
    try {
      final ok = await _channel
          .invokeMethod<bool>('requestIgnoreBatteryOptimization');
      return ok ?? false;
    } on PlatformException catch (_) {
      return false;
    }
  }
}
