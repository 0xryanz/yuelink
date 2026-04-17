import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Version string from pubspec.yaml (single source of truth).
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return info.version;
});

/// App-wide constants.
class AppConstants {
  AppConstants._();

  static const appName = 'YueLink';
  static const appBrand = 'Yue.to';
  static const packageName = 'com.yueto.yuelink';

  static const configFileName = 'yuelink.yaml';
  static const userAgent = 'clash.meta';

  /// Default test URL for latency testing.
  static const defaultTestUrl = 'https://www.gstatic.com/generate_204';
  static const defaultTestTimeout = 5000; // ms

  /// Default ports (aligned with standard mihomo config).
  static const defaultMixedPort = 7890;
  static const defaultApiPort = 9090;
  static const defaultDesktopTunStack = 'mixed';
  static const serviceListenHost = '127.0.0.1';
  static const serviceListenPort = 28653;
  static const desktopServiceName = 'YueLinkServiceHelper';
  static const desktopServiceLabel = 'com.yueto.yuelink.service';

  /// YueOps operations API base URL.
  static const yueOpsBaseUrl = 'https://ops.yue.to';

  /// Subscription URL host-substitution fallbacks. When a subscription fetch
  /// fails because the apex host is blocked/slow, the repository will retry
  /// with each entry swapped in place of the original host. Order matters:
  /// first entry is tried first.
  ///
  /// Empty by default — operator fills these in per-deployment. Example:
  ///   subscriptionFallbackHosts: [
  ///     'sub-backup.yue.to',         // second regional CDN
  ///     'sub.yuelink-cdn.pages.dev', // Cloudflare Pages mirror
  ///   ]
  /// Only YueLink-owned mirrors should appear here — a mismatched host could
  /// serve a poisoned config.
  static const List<String> subscriptionFallbackHosts = <String>[];
}
