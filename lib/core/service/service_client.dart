import 'dart:convert';
import 'dart:io';

import '../../constants.dart';
import '../storage/settings_service.dart';
import 'service_models.dart';

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

  static Future<DesktopServiceInfo> start({
    required String configYaml,
    required String homeDir,
  }) async {
    final json = await _request(
      'POST',
      '/v1/start',
      body: <String, dynamic>{
        'config_yaml': configYaml,
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

  static Future<Map<String, dynamic>> _request(
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
    final client = HttpClient();

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
}
