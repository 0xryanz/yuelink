import '../transport/yuelink_http_client.dart';

/// 首页配置 API — 无需认证。共用 [YueLinkHttpClient] 传输层。
class HomeRepository {
  HomeRepository({int? proxyPort})
      : _http = YueLinkHttpClient(
          baseUrl: 'https://yue.yuebao.website',
          timeout: const Duration(seconds: 5),
          proxyPort: proxyPort,
        );

  final YueLinkHttpClient _http;

  /// GET /api/client/home → 返回首页配置 JSON，失败返回 null。
  Future<Map<String, dynamic>?> fetchHomeConfig() =>
      _http.tryGet('/api/client/home');
}
