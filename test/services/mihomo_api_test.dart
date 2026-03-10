import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/services/mihomo_api.dart';

void main() {
  group('MihomoApi', () {
    test('default configuration', () {
      final api = MihomoApi();
      expect(api.host, '127.0.0.1');
      expect(api.port, 9090);
      expect(api.secret, isNull);
    });

    test('custom configuration', () {
      final api = MihomoApi(host: '192.168.1.1', port: 9091, secret: 'test');
      expect(api.host, '192.168.1.1');
      expect(api.port, 9091);
      expect(api.secret, 'test');
    });

    test('isAvailable returns false when not reachable', () async {
      final api = MihomoApi(port: 1); // unlikely to have anything on port 1
      final available = await api.isAvailable();
      expect(available, false);
    });
  });

  group('MihomoApiException', () {
    test('toString format', () {
      final e = MihomoApiException(404, 'not found');
      expect(e.toString(), 'MihomoApiException(404): not found');
    });

    test('stores status code and body', () {
      final e = MihomoApiException(500, 'internal error');
      expect(e.statusCode, 500);
      expect(e.body, 'internal error');
    });
  });
}
