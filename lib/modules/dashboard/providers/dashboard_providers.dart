import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/kernel/core_manager.dart';
import '../../../providers/core_provider.dart';

class ExitIpInfo {
  const ExitIpInfo({
    required this.ip,
    this.countryCode = '',
    this.country = '',
    this.city = '',
    this.isp = '',
  });

  final String ip;
  final String countryCode;
  final String country;
  final String city;
  final String isp;

  String get flagEmoji {
    if (countryCode.length != 2) return '';
    return countryCode.toUpperCase().runes
        .map((r) => String.fromCharCode(r - 0x41 + 0x1F1E6))
        .join();
  }

  String get locationLine {
    if (country.isEmpty) return '';
    if (city.isEmpty || city == country) return country;
    return '$country · $city';
  }
}

/// Fetches the exit IP by making an HTTP request through mihomo's mixed-port:
///   - **rule/global**: route through `127.0.0.1:mixedPort` → IP echo service
///   - **direct**: fetch local public IP directly (no proxy)
///
/// This approach works regardless of proxy type, group structure, or whether
/// proxy-provider nodes expose a `server` field in the API.
final exitIpInfoProvider = FutureProvider.autoDispose<ExitIpInfo?>((ref) async {
  final status = ref.watch(coreStatusProvider);
  if (status != CoreStatus.running) return null;

  // Mock mode: no real proxy — fetch local public IP directly (same as direct mode)
  if (CoreManager.instance.isMockMode) {
    return _fetchPublicIp();
  }

  // Watch routing mode so the IP refreshes when user switches mode
  final routingMode = ref.watch(routingModeProvider);

  try {
    if (routingMode == 'direct') {
      debugPrint('[ExitIP] direct mode → fetching local IP');
      return _fetchPublicIp();
    }

    // Rule / Global mode → fetch IP through mihomo's mixed-port proxy
    final port = CoreManager.instance.mixedPort;
    debugPrint('[ExitIP] mode=$routingMode, fetching via proxy 127.0.0.1:$port');
    return _fetchIpViaProxy(port);
  } catch (e) {
    debugPrint('[ExitIP] unexpected error: $e');
    return null;
  }
});

/// Fetch IP via mihomo's mixed-port proxy → IP echo service.
/// This gets the actual exit IP regardless of proxy type or API limitations.
Future<ExitIpInfo?> _fetchIpViaProxy(int port) async {
  final client = HttpClient();
  client.findProxy = (uri) => 'PROXY 127.0.0.1:$port';
  client.connectionTimeout = const Duration(seconds: 10);
  client.badCertificateCallback = (_, __, ___) => true;
  try {
    final req = await client.getUrl(Uri.parse('https://api.ip.sb/geoip'));
    req.headers.set('User-Agent', 'YueLink/1.0');
    req.headers.set('Accept', 'application/json');
    final resp = await req.close().timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) {
      debugPrint('[ExitIP] proxy fetch HTTP ${resp.statusCode}');
      return null;
    }
    final body = await resp.transform(utf8.decoder).join();
    final data = jsonDecode(body) as Map<String, dynamic>;
    return ExitIpInfo(
      ip: data['ip'] as String? ?? '',
      countryCode: (data['country_code'] as String? ?? '').toUpperCase(),
      country: data['country'] as String? ?? '',
      city: data['city'] as String? ?? '',
      isp: data['isp'] as String? ?? '',
    );
  } catch (e) {
    debugPrint('[ExitIP] proxy fetch failed: $e');
    return null;
  } finally {
    client.close(force: true);
  }
}

/// Fetch the local public IP directly (no proxy) for direct mode.
Future<ExitIpInfo> _fetchPublicIp() async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 5);
  client.badCertificateCallback = (_, __, ___) => true;
  try {
    final req = await client.getUrl(Uri.parse('https://api.ip.sb/geoip'));
    req.headers.set('User-Agent', 'YueLink/1.0');
    req.headers.set('Accept', 'application/json');
    final resp = await req.close().timeout(const Duration(seconds: 5));
    if (resp.statusCode != 200) {
      debugPrint('[ExitIP] public IP fetch HTTP ${resp.statusCode}');
      return const ExitIpInfo(ip: 'DIRECT');
    }
    final body = await resp.transform(utf8.decoder).join();
    final data = jsonDecode(body) as Map<String, dynamic>;
    return ExitIpInfo(
      ip: data['ip'] as String? ?? 'DIRECT',
      countryCode: (data['country_code'] as String? ?? '').toUpperCase(),
      country: data['country'] as String? ?? '',
      city: data['city'] as String? ?? '',
      isp: data['isp'] as String? ?? '',
    );
  } catch (e) {
    debugPrint('[ExitIP] public IP fetch failed: $e');
    return const ExitIpInfo(ip: 'DIRECT');
  } finally {
    client.close(force: true);
  }
}

// Keep legacy alias so any remaining references compile
final proxyServerIpProvider = exitIpInfoProvider;
