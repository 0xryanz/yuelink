import 'dart:convert';
import 'dart:io';

import 'status_models.dart';

/// 网络状态 API（公开接口，无需认证）。
class StatusRepository {
  static const _baseUrl = 'https://status.yue.to';

  Future<StatusData> fetch() async {
    final results = await Future.wait([
      _get('/api/status/nodes'),
      _get('/api/status/incidents'),
    ]);

    final nodesJson = results[0];
    final incidentsJson = results[1];

    final regions = (nodesJson['regions'] as List<dynamic>? ?? [])
        .map((e) => StatusRegion.fromJson(e as Map<String, dynamic>))
        .toList();

    final incidents = (incidentsJson['incidents'] as List<dynamic>? ?? [])
        .map((e) => StatusIncident.fromJson(e as Map<String, dynamic>))
        .toList();

    return StatusData(
      regions: regions,
      incidents: incidents,
      updatedAt: nodesJson['updated_at'] as String? ?? '',
    );
  }

  Future<Map<String, dynamic>> _get(String path) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    try {
      final uri = Uri.parse('$_baseUrl$path');
      final request = await client.getUrl(uri);
      request.headers.set('Accept', 'application/json');
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      return jsonDecode(body) as Map<String, dynamic>;
    } finally {
      client.close();
    }
  }
}
