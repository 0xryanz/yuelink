import 'clash_core.dart';
import 'ffi/core_controller.dart';
import '../infrastructure/datasources/mihomo_api.dart';

/// [ClashCore] backed by FFI lifecycle + REST data.
///
/// Lifecycle calls (init/start/stop/etc.) delegate to [CoreController]
/// which talks to the Go core via dart:ffi. Data calls (getProxies/etc.)
/// delegate to [MihomoApi] which talks to mihomo's REST listener on
/// `127.0.0.1:9090`. The split is internal — callers see one
/// [ClashCore] interface.
///
/// Logs come from the websocket stream in real mode (`MihomoStream`),
/// not from this class — [getLogsSnapshot] returns an empty list.
class RealClashCore implements ClashCore {
  RealClashCore(this._api);

  final MihomoApi _api;
  final CoreController _ffi = CoreController.instance;

  @override
  bool get isMockMode => false;

  // ── Lifecycle (FFI) ───────────────────────────────────────────────────
  @override
  String? init(String homeDir) => _ffi.init(homeDir);

  @override
  String? start(String configYaml) => _ffi.start(configYaml);

  @override
  void stop() => _ffi.stop();

  @override
  void shutdown() => _ffi.shutdown();

  @override
  bool get isRunning => _ffi.isRunning;

  @override
  bool validateConfig(String configYaml) => _ffi.validateConfig(configYaml);

  @override
  String? updateConfig(String configYaml) => _ffi.updateConfig(configYaml);

  // ── Data (REST) ───────────────────────────────────────────────────────
  @override
  Future<Map<String, dynamic>> getProxies() => _api.getProxies();

  @override
  Future<bool> changeProxy(String groupName, String proxyName) =>
      _api.changeProxy(groupName, proxyName);

  @override
  Future<int> testDelay(String proxyName,
      {String url = '', int timeoutMs = 5000}) {
    // MihomoApi uses 'timeout' as the param name and a default URL — pass
    // through here, defaulting URL to MihomoApi's own default if blank.
    if (url.isEmpty) {
      return _api.testDelay(proxyName, timeout: timeoutMs);
    }
    return _api.testDelay(proxyName, url: url, timeout: timeoutMs);
  }

  @override
  Future<({int up, int down})> getTraffic() => _api.getTraffic();

  @override
  Future<Map<String, dynamic>> getConnections() => _api.getConnections();

  @override
  Future<Map<String, dynamic>> getRules() => _api.getRules();

  /// Real mode delivers logs via the websocket stream (`MihomoStream`).
  /// This snapshot accessor returns an empty list — callers that want logs
  /// in real mode should subscribe to the stream instead.
  @override
  List<Map<String, String>> getLogsSnapshot() => const [];
}
