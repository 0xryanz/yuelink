import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../constants.dart';
import '../storage/settings_service.dart';
import 'service_models.dart';

/// HTTP-style client for talking to the YueLink desktop service helper.
///
/// Transport selection (matches helper-side build tags):
/// - macOS / Linux: Unix domain socket at the path stored in
///   [SettingsService.getServiceSocketPath]. The helper authenticates the
///   caller via OS peer credentials (`SO_PEERCRED` / `LOCAL_PEERCRED`); no
///   token is sent or stored on these platforms.
/// - Windows: HTTP loopback (127.0.0.1:port) with a bearer token in
///   `X-YueLink-Token` header. Token is stored in settings.json. (Named
///   Pipe support in Dart is non-trivial; documented limitation.)
///
/// Both transports speak HTTP/1.1 framing on top of the chosen socket type
/// — the request line, headers, and body format are identical so the
/// server-side handler is shared (`runtime.newHandler()`).
class ServiceClient {
  ServiceClient._();

  static Future<bool> ping() async {
    try {
      await _request('GET', '/v1/ping');
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<DesktopServiceInfo> status() async {
    final json = await _request('GET', '/v1/status');
    return DesktopServiceInfo.fromJson(
      json,
      installed: true,
      reachable: true,
    );
  }

  /// Start mihomo via the helper.
  ///
  /// IMPORTANT: [configPath] must be an ABSOLUTE path to a YAML file the
  /// **client** has already written. The helper will validate the path
  /// against its install-time allowlist and READ the content from disk —
  /// it does NOT accept raw config content over the wire anymore.
  /// This eliminates the "client → root file write" attack surface from
  /// the previous design where `config_yaml` was a request body field.
  static Future<DesktopServiceInfo> start({
    required String configPath,
    required String homeDir,
  }) async {
    final json = await _request(
      'POST',
      '/v1/start',
      body: <String, dynamic>{
        'config_path': configPath,
        'home_dir': homeDir,
      },
    );
    return DesktopServiceInfo.fromJson(
      json,
      installed: true,
      reachable: true,
    );
  }

  static Future<DesktopServiceInfo> stop() async {
    final json = await _request('POST', '/v1/stop');
    return DesktopServiceInfo.fromJson(
      json,
      installed: true,
      reachable: true,
    );
  }

  static Future<String?> version() async {
    try {
      final json = await _request('GET', '/v1/version');
      return json['version'] as String?;
    } catch (_) {
      return null;
    }
  }

  static Future<String> logs({int lines = 200}) async {
    final json = await _request('GET', '/v1/logs?lines=$lines');
    return json['content'] as String? ?? '';
  }

  // ── Transport ──────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    if (Platform.isMacOS || Platform.isLinux) {
      return _unixSocketRequest(method, path, body: body);
    }
    return _httpLoopbackRequest(method, path, body: body);
  }

  /// Speak HTTP/1.1 over a Unix domain socket. Dart's [HttpClient] doesn't
  /// expose a hook for unix sockets, so we hand-frame the request and parse
  /// the response. The framing is intentionally minimal (no chunked, no
  /// keep-alive — every call is a fresh connection).
  static Future<Map<String, dynamic>> _unixSocketRequest(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final socketPath = await SettingsService.getServiceSocketPath();
    if (socketPath == null || socketPath.isEmpty) {
      throw StateError('Desktop service socket path is missing');
    }
    final socket = await Socket.connect(
      InternetAddress(socketPath, type: InternetAddressType.unix),
      0,
      timeout: const Duration(seconds: 3),
    );
    try {
      final bodyBytes = body == null ? <int>[] : utf8.encode(jsonEncode(body));
      final headers = StringBuffer()
        ..write('$method $path HTTP/1.1\r\n')
        ..write('Host: localhost\r\n')
        ..write('Accept: application/json\r\n')
        ..write('Connection: close\r\n');
      if (body != null) {
        headers
          ..write('Content-Type: application/json\r\n')
          ..write('Content-Length: ${bodyBytes.length}\r\n');
      }
      headers.write('\r\n');
      socket.add(utf8.encode(headers.toString()));
      if (bodyBytes.isNotEmpty) socket.add(bodyBytes);
      await socket.flush();

      // Read entire response (small JSON, single connection)
      final raw = <int>[];
      await for (final chunk
          in socket.timeout(const Duration(seconds: 5))) {
        raw.addAll(chunk);
      }
      return _parseHttpResponse(raw);
    } finally {
      try {
        await socket.close();
      } catch (_) {}
      socket.destroy();
    }
  }

  /// Legacy Windows path: HTTP loopback + bearer token. Kept until Named
  /// Pipe support lands in Dart.
  static Future<Map<String, dynamic>> _httpLoopbackRequest(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final token = await SettingsService.getServiceAuthToken();
    if (token == null || token.isEmpty) {
      throw StateError('Desktop service auth token is missing');
    }
    final port = await SettingsService.getServicePort() ??
        AppConstants.serviceListenPort;
    // Bypass system proxy for the same reason XBoardApi.buildClient does:
    // YueLink may set its OWN system proxy to 127.0.0.1:mixedPort, and
    // default Dart HttpClient behaviour is to respect system proxy
    // settings. Even 127.0.0.1 isn't guaranteed to be in the bypass list
    // on every OS / user config (Windows ProxyOverride is user-editable).
    // `DIRECT` makes this transport immune to whatever mihomo state is.
    final client = HttpClient();
    client.findProxy = (uri) => 'DIRECT';

    try {
      final request = await client
          .openUrl(
            method,
            Uri(
              scheme: 'http',
              host: AppConstants.serviceListenHost,
              port: port,
              path: path.split('?').first,
              query: path.contains('?') ? path.split('?').last : null,
            ),
          )
          .timeout(const Duration(seconds: 3));

      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set('X-YueLink-Token', token);

      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }

      final response =
          await request.close().timeout(const Duration(seconds: 5));
      final payload = await utf8.decodeStream(response).timeout(
            const Duration(seconds: 5),
          );
      final json = payload.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(payload) as Map<String, dynamic>;

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = json['error'] as String? ??
            'service request failed (${response.statusCode})';
        throw HttpException(message, uri: request.uri);
      }

      return json;
    } finally {
      client.close(force: true);
    }
  }

  /// Parse a minimal HTTP/1.1 response (status line + headers + body) into
  /// the JSON body. Throws on non-2xx status.
  static Map<String, dynamic> _parseHttpResponse(List<int> raw) {
    final text = utf8.decode(raw);
    final headerEnd = text.indexOf('\r\n\r\n');
    if (headerEnd < 0) {
      throw const FormatException('helper response has no header terminator');
    }
    final head = text.substring(0, headerEnd);
    final bodyText = text.substring(headerEnd + 4);

    final firstLineEnd = head.indexOf('\r\n');
    final statusLine =
        firstLineEnd < 0 ? head : head.substring(0, firstLineEnd);
    final parts = statusLine.split(' ');
    if (parts.length < 3) {
      throw FormatException('bad status line: $statusLine');
    }
    final status = int.tryParse(parts[1]) ?? 0;
    final json = bodyText.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(bodyText) as Map<String, dynamic>;
    if (status < 200 || status >= 300) {
      final message = json['error'] as String? ??
          'service request failed ($status)';
      throw HttpException(message);
    }
    return json;
  }
}
