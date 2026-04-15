import '../../domain/account/account_overview.dart';
import '../../domain/account/notice.dart';
import '../transport/yuelink_http_client.dart';

/// Repository for account overview and quick-action link data.
///
/// Uses the same standalone YueLink Checkin API server (yue.yuebao.website)
/// as [CheckinRepository], with shared transport via [YueLinkHttpClient].
class AccountRepository {
  AccountRepository()
      : _http = YueLinkHttpClient(baseUrl: 'https://yue.yuebao.website');

  final YueLinkHttpClient _http;

  /// Fetch account overview for the current user.
  /// GET /api/client/account/overview  (Bearer token required)
  /// Returns null on any error so the UI can show an error state without crashing.
  Future<AccountOverview?> getAccountOverview(String token) async {
    try {
      final data =
          await _http.get('/api/client/account/overview', token: token);
      return AccountOverview.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  /// Fetch user notices (Bearer token required).
  /// GET /api/client/account/notices
  /// Returns empty list on any error.
  Future<List<AccountNotice>> getNotices(String token) async {
    try {
      final list =
          await _http.getList('/api/client/account/notices', token: token);
      return list.map(AccountNotice.fromJson).toList();
    } catch (_) {
      return [];
    }
  }
}
