import 'package:flutter/foundation.dart';

/// Release-safe debug log. No-op in release builds.
void debugLog(String message) {
  if (kDebugMode) {
    debugPrint(message);
  }
}
