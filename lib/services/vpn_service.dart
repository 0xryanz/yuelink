import 'dart:io';

import 'package:flutter/services.dart';

/// Platform-specific VPN service abstraction.
///
/// Handles starting/stopping the OS-level VPN tunnel:
/// - Android: VpnService
/// - iOS/macOS: NEPacketTunnelProvider
/// - Windows: wintun / system proxy
/// - Linux: TUN device / system proxy
class VpnService {
  static const _channel = MethodChannel('com.yueto.yuelink/vpn');

  /// Start the platform VPN tunnel.
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
  /// Returns true if permission is already granted or successfully obtained.
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
}
