import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// REST client for YueOps operations API.
///
/// Provides lightweight public endpoints for:
/// - Carrier detection (IP → CT/CU/CM)
/// - SNI/BestCF configuration for client optimization
class YueOpsApi {
  YueOpsApi({required this.baseUrl});

  final String baseUrl;

  static const _kTimeout = Duration(seconds: 10);

  static http.Client _buildClient() {
    final inner = HttpClient();
    inner.connectionTimeout = const Duration(seconds: 10);
    inner.idleTimeout = const Duration(seconds: 15);
    return IOClient(inner);
  }

  /// Get current SNI + BestCF carrier config for client optimization.
  ///
  /// Returns [ClientConfig] with SNI domain, carrier IPs, node mapping.
  /// Public endpoint — no authentication required.
  Future<ClientConfig> getConfig() async {
    final client = _buildClient();
    try {
      final resp = await client
          .get(Uri.parse('$baseUrl/api/client/config'))
          .timeout(_kTimeout);
      if (resp.statusCode != 200) {
        throw YueOpsApiException('Config fetch failed: ${resp.statusCode}');
      }
      Map<String, dynamic> json;
      try {
        json = jsonDecode(resp.body) as Map<String, dynamic>;
      } catch (e) {
        throw YueOpsApiException(
            'Invalid JSON response from YueOps: ${resp.statusCode}');
      }
      return ClientConfig.fromJson(json);
    } finally {
      client.close();
    }
  }

  /// Detect carrier from client IP using server-side ASN database.
  ///
  /// Returns [CarrierInfo] with carrier type and recommended node.
  /// Public endpoint — no authentication required.
  Future<CarrierInfo> detectCarrier(String ip) async {
    final client = _buildClient();
    try {
      final uri = Uri.parse('$baseUrl/api/client/carrier').replace(
        queryParameters: {'ip': ip},
      );
      final resp = await client.get(uri).timeout(_kTimeout);
      if (resp.statusCode != 200) {
        throw YueOpsApiException('Carrier detect failed: ${resp.statusCode}');
      }
      Map<String, dynamic> json;
      try {
        json = jsonDecode(resp.body) as Map<String, dynamic>;
      } catch (e) {
        throw YueOpsApiException(
            'Invalid JSON response from YueOps: ${resp.statusCode}');
      }
      return CarrierInfo.fromJson(json);
    } finally {
      client.close();
    }
  }
}

// ── Models ──────────────────────────────────────────────────────────────────

class ClientConfig {
  final String sniDomain;
  final String sniStatus;
  final Map<String, CarrierEntry> carriers;
  final Map<String, String> nodeMapping;

  const ClientConfig({
    required this.sniDomain,
    required this.sniStatus,
    required this.carriers,
    required this.nodeMapping,
  });

  factory ClientConfig.fromJson(Map<String, dynamic> json) {
    final carriersRaw =
        (json['carriers'] is Map ? json['carriers'] as Map<String, dynamic> : null) ?? {};
    final carriers = carriersRaw.map((k, v) {
      final entry = v is Map<String, dynamic> ? v : <String, dynamic>{};
      return MapEntry(
        k,
        CarrierEntry(
          domain: entry['domain']?.toString() ?? '',
          name: entry['name']?.toString() ?? '',
        ),
      );
    });

    final nodeMappingRaw =
        (json['node_mapping'] is Map ? json['node_mapping'] as Map<String, dynamic> : null) ?? {};
    final nodeMapping =
        nodeMappingRaw.map((k, v) => MapEntry(k, v?.toString() ?? ''));

    return ClientConfig(
      sniDomain: json['sni_domain']?.toString() ?? '',
      sniStatus: json['sni_status']?.toString() ?? 'unknown',
      carriers: carriers,
      nodeMapping: nodeMapping,
    );
  }

  /// Whether SNI is healthy (not blocked or degraded).
  bool get isSniHealthy => sniStatus == 'healthy';
}

class CarrierEntry {
  final String domain;
  final String name;
  const CarrierEntry({required this.domain, required this.name});
}

class CarrierInfo {
  final String ip;
  final String? carrier;
  final String carrierName;
  final String? recommendedNodeId;

  const CarrierInfo({
    required this.ip,
    this.carrier,
    required this.carrierName,
    this.recommendedNodeId,
  });

  factory CarrierInfo.fromJson(Map<String, dynamic> json) {
    return CarrierInfo(
      ip: json['ip']?.toString() ?? '',
      carrier: json['carrier']?.toString(),
      carrierName: json['carrier_name']?.toString() ?? '',
      recommendedNodeId: json['recommended_node_id']?.toString(),
    );
  }

  /// Whether a Chinese carrier was detected.
  bool get isDetected => carrier != null && carrier!.isNotEmpty;
}

class YueOpsApiException implements Exception {
  final String message;
  const YueOpsApiException(this.message);
  @override
  String toString() => 'YueOpsApiException: $message';
}
