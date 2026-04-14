import 'dart:convert';
import 'dart:io';

import '../../domain/emby/emby_info_entity.dart';

/// Fetches Emby service info from the YueOps client API (yue.yuebao.website).
///
/// Emby user management is on a separate server from XBoard,
/// so this repository calls the checkin-api backend directly.
class EmbyRepository {
  static const _baseUrl = 'https://yue.yuebao.website';

  /// Returns Emby info for the current user, or null if no access.
  Future<EmbyInfo?> getEmby(String token) async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(
        Uri.parse('$_baseUrl/api/client/emby'),
      );
      request.headers.set('Authorization', token);
      request.headers.set('Accept', 'application/json');
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode == 401) return null;
      if (response.statusCode != 200) return null;

      final json = jsonDecode(body) as Map<String, dynamic>;
      if (json['status'] != 'success') return null;

      final data = json['data'] as Map<String, dynamic>?;
      if (data == null) return null;

      return EmbyInfo.fromJson(data);
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }
}
