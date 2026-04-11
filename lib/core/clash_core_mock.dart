import 'clash_core.dart';
import 'ffi/core_mock.dart';

/// [ClashCore] backed by [CoreMock].
///
/// Used when the native Go library is unavailable (mock UI development
/// mode). Lifecycle and data both delegate to the same [CoreMock]
/// singleton — there is no FFI/REST split in mock mode.
///
/// `validateConfig` always returns true, MITM operations are no-ops, and
/// the data methods return canned content from `CoreMock`.
class MockClashCore implements ClashCore {
  MockClashCore();

  final CoreMock _mock = CoreMock.instance;

  @override
  bool get isMockMode => true;

  // ── Lifecycle ────────────────────────────────────────────────────────
  @override
  String? init(String homeDir) {
    _mock.init(homeDir);
    return null;
  }

  @override
  String? start(String configYaml) {
    final ok = _mock.start(configYaml);
    return ok ? null : 'mock start failed (not initialized)';
  }

  @override
  void stop() => _mock.stop();

  @override
  void shutdown() => _mock.shutdown();

  @override
  bool get isRunning => _mock.isRunning;

  @override
  bool validateConfig(String configYaml) => _mock.validateConfig(configYaml);

  @override
  String? updateConfig(String configYaml) {
    _mock.updateConfig(configYaml);
    return null;
  }

  // ── Data ─────────────────────────────────────────────────────────────
  // CoreMock methods are synchronous — wrap in Future.value to satisfy
  // the async interface contract. Callers always `await` so they don't
  // notice the difference.

  @override
  Future<Map<String, dynamic>> getProxies() async => _mock.getProxies();

  @override
  Future<bool> changeProxy(String groupName, String proxyName) async =>
      _mock.changeProxy(groupName, proxyName);

  @override
  Future<int> testDelay(String proxyName,
          {String url = '', int timeoutMs = 5000}) async =>
      _mock.testDelay(proxyName, url: url, timeoutMs: timeoutMs);

  @override
  Future<({int up, int down})> getTraffic() async => _mock.getTraffic();

  @override
  Future<Map<String, dynamic>> getConnections() async => _mock.getConnections();

  @override
  Future<Map<String, dynamic>> getRules() async => _mock.getRules();

  @override
  List<Map<String, String>> getLogsSnapshot() => _mock.getLogs();
}
