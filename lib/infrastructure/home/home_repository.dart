import 'dart:convert';
import 'dart:io';

/// 首页配置 API — 无需认证。
class HomeRepository {
  static const _baseUrl = 'https://yue.yuebao.website';

  /// GET /api/client/home → 返回首页配置 JSON，失败返回 null。
  Future<Map<String, dynamic>?> fetchHomeConfig() async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 5);
    try {
      final uri = Uri.parse('$_baseUrl/api/client/home');
      final request = await client.getUrl(uri);
      request.headers.set('Accept', 'application/json');
      final response = await request.close();
      if (response.statusCode != 200) return null;
      final body = await response.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      return json['data'] as Map<String, dynamic>?;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }
}
