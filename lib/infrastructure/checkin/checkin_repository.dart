import '../../domain/checkin/checkin_result_entity.dart';
import '../datasources/xboard/index.dart';
import '../transport/yuelink_http_client.dart';

/// Repository for check-in operations via YueLink Checkin API.
///
/// The check-in API runs as a standalone service on yue.yuebao.website,
/// separate from the XBoard panel. Uses the same XBoard Sanctum token
/// for authentication.
///
/// Transport (HttpClient + Bearer + status-code asserts) is shared with
/// [AccountRepository] and [HomeRepository] via [YueLinkHttpClient].
class CheckinRepository {
  CheckinRepository({int? proxyPort})
      : _http = YueLinkHttpClient(
          baseUrl: 'https://yue.yuebao.website',
          proxyPort: proxyPort,
        );

  final YueLinkHttpClient _http;

  /// Perform a check-in.
  /// POST /api/client/checkin
  Future<CheckinResult> checkin(String token) async {
    final data = await _http.post('/api/client/checkin', token: token);
    return CheckinResult.fromJson(data);
  }

  /// Get current check-in status for today.
  /// GET /api/client/checkin/status
  Future<CheckinResult?> getCheckinStatus(String token) async {
    try {
      final data = await _http.get('/api/client/checkin/status', token: token);
      return CheckinResult.fromJson(data);
    } on XBoardApiException catch (e) {
      // 404 = endpoint not ready yet, treat as not checked in
      if (e.statusCode == 404) return null;
      rethrow;
    } catch (_) {
      return null;
    }
  }
}
