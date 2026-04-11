/// The single API surface for all clash/mihomo operations.
///
/// Was previously split across:
///   - `CoreController` (FFI lifecycle methods + 4 mock-only data stubs)
///   - `MihomoApi` (REST data methods, real mode only)
///   - `CoreMock` (mock data, called directly with `CoreMock.instance.X()`)
///
/// The split forced every caller to ask "am I in mock mode?" and dispatch
/// manually. The CLAUDE.md rule "never add FFI bindings for data operations"
/// existed only because the seam was hand-policed. With one interface, the
/// rule is automatic — there is no place to put a data method except here,
/// and both implementations must satisfy it.
///
/// FlClash uses the same pattern (`lib/core/interface.dart` →
/// `CoreLib` / `CoreService`). YueLink's variant: real mode delegates
/// lifecycle to FFI bindings and data to `MihomoApi`; mock mode delegates
/// everything to `CoreMock`. Both are invisible to callers — they just
/// see [ClashCore].
///
/// Streaming data (traffic websocket, connections websocket, logs websocket)
/// stays in the dedicated repositories — those are real-mode-only and the
/// mock equivalents are timer-based polls in the providers themselves.
/// This interface only covers the operations that have BOTH a real-mode and
/// a mock-mode implementation, which is where the duality pain lives.
abstract class ClashCore {
  // ── Lifecycle ────────────────────────────────────────────────────────────

  /// Whether this implementation is the mock fallback (no native library).
  /// Production code should rarely care — if you're tempted to gate logic
  /// on this, ask whether the gate should live inside the implementation
  /// instead.
  bool get isMockMode;

  /// Initialise the core. Returns null on success, error message on failure.
  String? init(String homeDir);

  /// Start the core with a Clash YAML config. Returns null on success.
  String? start(String configYaml);

  /// Stop the running core. Idempotent.
  void stop();

  /// Tear down all core resources (used on app exit).
  void shutdown();

  /// Whether the core is currently running.
  bool get isRunning;

  /// Validate a Clash YAML config without starting the core.
  bool validateConfig(String configYaml);

  /// Hot-reload a Clash YAML config. Returns null on success.
  String? updateConfig(String configYaml);

  // ── Data ─────────────────────────────────────────────────────────────────
  //
  // Snapshot operations (one-shot reads). For real-time streams (traffic,
  // connections, logs) use the dedicated repositories — those have separate
  // websocket / polling code paths.

  /// Fetch the current proxy groups + members. Returns the raw mihomo
  /// `/proxies` response shape: `{"proxies": {<name>: {type, now, all}, ...}}`.
  Future<Map<String, dynamic>> getProxies();

  /// Switch the selected proxy of [groupName] to [proxyName]. Returns true
  /// on success.
  Future<bool> changeProxy(String groupName, String proxyName);

  /// Test the latency of a proxy. Returns the delay in milliseconds, or
  /// `-1` if the test failed. [url] defaults to the test URL configured
  /// in user settings; [timeoutMs] is the per-request timeout.
  Future<int> testDelay(String proxyName,
      {String url = '', int timeoutMs = 5000});

  /// Fetch the current traffic counters (one sample, not a stream).
  Future<({int up, int down})> getTraffic();

  /// Fetch the current connections snapshot. Same shape as the websocket
  /// `/connections` payload: `{connections: [...], uploadTotal, downloadTotal}`.
  Future<Map<String, dynamic>> getConnections();

  /// Fetch the current rule list. Shape: `{rules: [{type, payload, proxy}, ...]}`.
  Future<Map<String, dynamic>> getRules();

  /// Fetch a snapshot of recent logs (mock mode only — real mode uses the
  /// websocket stream via `MihomoStream`). Returns an empty list when not
  /// running. Real mode returns an empty list because logs are pushed via
  /// websocket; this method exists so the interface stays symmetric.
  List<Map<String, String>> getLogsSnapshot();
}
