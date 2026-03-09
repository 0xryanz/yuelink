import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'core_bindings.dart';
import 'core_mock.dart';

/// High-level Dart wrapper around the mihomo Go core.
///
/// Automatically falls back to [CoreMock] when the native library
/// is not available (development mode without compiled Go core).
class CoreController {
  CoreController._() {
    try {
      _bindings = CoreBindings.instance;
      _useMock = false;
    } catch (_) {
      // Native library not found — use mock for UI development
      _useMock = true;
    }
  }

  static CoreController? _instance;
  static CoreController get instance => _instance ??= CoreController._();

  late final CoreBindings? _bindings;
  late final bool _useMock;
  final _mock = CoreMock.instance;

  /// Whether running in mock mode (no native library).
  bool get isMockMode => _useMock;

  // ------------------------------------------------------------------
  // Lifecycle
  // ------------------------------------------------------------------

  bool init(String homeDir) {
    if (_useMock) return _mock.init(homeDir);
    final ptr = homeDir.toNativeUtf8();
    try {
      return _bindings!.initCore(ptr) == 0;
    } finally {
      calloc.free(ptr);
    }
  }

  bool start(String configYaml) {
    if (_useMock) return _mock.start(configYaml);
    final ptr = configYaml.toNativeUtf8();
    try {
      return _bindings!.startCore(ptr) == 0;
    } finally {
      calloc.free(ptr);
    }
  }

  void stop() {
    if (_useMock) return _mock.stop();
    _bindings!.stopCore();
  }

  void shutdown() {
    if (_useMock) return _mock.shutdown();
    _bindings!.shutdown();
  }

  bool get isRunning {
    if (_useMock) return _mock.isRunning;
    return _bindings!.isRunning() == 1;
  }

  // ------------------------------------------------------------------
  // Configuration
  // ------------------------------------------------------------------

  bool validateConfig(String configYaml) {
    if (_useMock) return _mock.validateConfig(configYaml);
    final ptr = configYaml.toNativeUtf8();
    try {
      return _bindings!.validateConfig(ptr) == 0;
    } finally {
      calloc.free(ptr);
    }
  }

  bool updateConfig(String configYaml) {
    if (_useMock) return _mock.updateConfig(configYaml);
    final ptr = configYaml.toNativeUtf8();
    try {
      return _bindings!.updateConfig(ptr) == 0;
    } finally {
      calloc.free(ptr);
    }
  }

  // ------------------------------------------------------------------
  // Proxies
  // ------------------------------------------------------------------

  Map<String, dynamic> getProxies() {
    if (_useMock) return _mock.getProxies();
    return _callJsonFunction(_bindings!.getProxies);
  }

  bool changeProxy(String groupName, String proxyName) {
    if (_useMock) return _mock.changeProxy(groupName, proxyName);
    final gPtr = groupName.toNativeUtf8();
    final pPtr = proxyName.toNativeUtf8();
    try {
      return _bindings!.changeProxy(gPtr, pPtr) == 0;
    } finally {
      calloc.free(gPtr);
      calloc.free(pPtr);
    }
  }

  int testDelay(String proxyName,
      {String url = 'https://www.gstatic.com/generate_204',
      int timeoutMs = 5000}) {
    if (_useMock) return _mock.testDelay(proxyName);
    final nPtr = proxyName.toNativeUtf8();
    final uPtr = url.toNativeUtf8();
    try {
      return _bindings!.testDelay(nPtr, uPtr, timeoutMs);
    } finally {
      calloc.free(nPtr);
      calloc.free(uPtr);
    }
  }

  // ------------------------------------------------------------------
  // Traffic & Connections
  // ------------------------------------------------------------------

  ({int up, int down}) getTraffic() {
    if (_useMock) return _mock.getTraffic();
    final data = _callJsonFunction(_bindings!.getTraffic);
    return (
      up: (data['up'] as num?)?.toInt() ?? 0,
      down: (data['down'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> getConnections() {
    if (_useMock) return _mock.getConnections();
    return _callJsonFunction(_bindings!.getConnections);
  }

  bool closeConnection(String connId) {
    if (_useMock) return _mock.closeConnection(connId);
    final ptr = connId.toNativeUtf8();
    try {
      return _bindings!.closeConnection(ptr) == 0;
    } finally {
      calloc.free(ptr);
    }
  }

  void closeAllConnections() {
    if (_useMock) return _mock.closeAllConnections();
    _bindings!.closeAllConnections();
  }

  // ------------------------------------------------------------------
  // Helpers
  // ------------------------------------------------------------------

  Map<String, dynamic> _callJsonFunction(Pointer<dynamic> Function() fn) {
    final ptr = fn();
    try {
      final utf8Ptr = ptr.cast<Utf8>();
      final jsonStr = utf8Ptr.toDartString();
      return json.decode(jsonStr) as Map<String, dynamic>;
    } finally {
      _bindings!.freeCString(ptr.cast<Utf8>());
    }
  }
}
