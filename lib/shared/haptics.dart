import 'dart:io';

import 'package:flutter/services.dart';

/// Centralized haptic feedback. Keep calls semantic — think "what kind
/// of touch event is this" instead of "which intensity preset".
///
/// Native platforms only. Desktop calls are no-ops because `HapticFeedback`
/// has no meaning there and some desktop platforms throw.
class Haptics {
  const Haptics._();

  static bool get _enabled => Platform.isIOS || Platform.isAndroid;

  /// Light tap — list tile tap, toggle flip, tab switch.
  static Future<void> selection() async {
    if (!_enabled) return;
    try {
      await HapticFeedback.selectionClick();
    } catch (_) {}
  }

  /// Medium thud — confirmation, primary action (connect/disconnect,
  /// submit form, copy to clipboard).
  static Future<void> medium() async {
    if (!_enabled) return;
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  /// Heavy thud — destructive action completed, transition between
  /// major app modes, VPN-connected moment.
  static Future<void> heavy() async {
    if (!_enabled) return;
    try {
      await HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  /// Light success tick — after a short operation completes (sync done,
  /// profile saved). Cheaper than medium so doesn't feel "loud".
  static Future<void> success() async {
    if (!_enabled) return;
    try {
      await HapticFeedback.lightImpact();
    } catch (_) {}
  }

  /// Vibration pattern for errors — uses heavy impact followed by
  /// light impact to mimic iOS "notification error" haptic. Android
  /// lacks a direct equivalent; heavy is the closest native call.
  static Future<void> error() async {
    if (!_enabled) return;
    try {
      await HapticFeedback.heavyImpact();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await HapticFeedback.lightImpact();
    } catch (_) {}
  }
}
