import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/ffi/core_mock.dart';

void main() {
  late CoreMock mock;

  setUp(() {
    // Create a fresh instance for each test
    mock = CoreMock.instance;
    mock.shutdown(); // Reset state
  });

  group('CoreMock lifecycle', () {
    test('init and start', () {
      expect(mock.isRunning, false);

      mock.init('/tmp/test');
      expect(mock.isRunning, false);

      final ok = mock.start('config: test');
      expect(ok, true);
      expect(mock.isRunning, true);
    });

    test('start fails without init', () {
      final ok = mock.start('config: test');
      expect(ok, false);
      expect(mock.isRunning, false);
    });

    test('stop', () {
      mock.init('/tmp/test');
      mock.start('config: test');
      expect(mock.isRunning, true);

      mock.stop();
      expect(mock.isRunning, false);
    });

    test('shutdown resets everything', () {
      mock.init('/tmp/test');
      mock.start('config: test');
      mock.shutdown();
      expect(mock.isRunning, false);

      // Can't start after shutdown without re-init
      final ok = mock.start('config: test');
      expect(ok, false);
    });
  });

  group('CoreMock proxies', () {
    test('getProxies returns empty when not running', () {
      mock.init('/tmp/test');
      final data = mock.getProxies();
      expect(data['proxies'], isA<Map>());
      expect((data['proxies'] as Map).isEmpty, true);
    });

    test('getProxies returns groups when running', () {
      mock.init('/tmp/test');
      mock.start('');
      final data = mock.getProxies();
      final proxies = data['proxies'] as Map<String, dynamic>;

      expect(proxies.containsKey('节点选择'), true);
      expect(proxies.containsKey('自动选择'), true);
      expect(proxies.containsKey('流媒体'), true);
      expect(proxies.containsKey('AI 服务'), true);
    });

    test('changeProxy updates selection', () {
      mock.init('/tmp/test');
      mock.start('');

      mock.changeProxy('节点选择', '🇯🇵 日本 01');

      final data = mock.getProxies();
      final group = data['proxies']['节点选择'] as Map<String, dynamic>;
      expect(group['now'], '🇯🇵 日本 01');
    });

    test('testDelay returns realistic values', () {
      mock.init('/tmp/test');
      mock.start('');

      final hkDelay = mock.testDelay('🇭🇰 香港 01');
      expect(hkDelay, greaterThan(0));
      expect(hkDelay, lessThan(500));

      final usDelay = mock.testDelay('🇺🇸 美国 01');
      expect(usDelay, greaterThan(0));
    });

    test('testDelay returns -1 when not running', () {
      mock.init('/tmp/test');
      final delay = mock.testDelay('🇭🇰 香港 01');
      expect(delay, -1);
    });
  });

  group('CoreMock traffic', () {
    test('getTraffic returns zero when not running', () {
      mock.init('/tmp/test');
      final t = mock.getTraffic();
      expect(t.up, 0);
      expect(t.down, 0);
    });

    test('getTraffic returns data when running', () {
      mock.init('/tmp/test');
      mock.start('');
      final t = mock.getTraffic();
      // Random values, just check they're non-negative
      expect(t.up, greaterThanOrEqualTo(0));
      expect(t.down, greaterThanOrEqualTo(0));
    });
  });

  group('CoreMock connections', () {
    test('getConnections returns data when running', () {
      mock.init('/tmp/test');
      mock.start('');
      final data = mock.getConnections();

      expect(data['connections'], isA<List>());
      expect((data['connections'] as List).isNotEmpty, true);
      expect(data['uploadTotal'], isA<int>());
      expect(data['downloadTotal'], isA<int>());
    });
  });
}
