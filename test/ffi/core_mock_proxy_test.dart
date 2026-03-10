import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/ffi/core_mock.dart';

void main() {
  late CoreMock mock;

  setUp(() {
    mock = CoreMock.instance;
    mock.shutdown();
    mock.init('/tmp/test');
    mock.start('');
  });

  group('CoreMock proxy groups', () {
    test('has expected groups', () {
      final data = mock.getProxies();
      final proxies = data['proxies'] as Map<String, dynamic>;

      expect(proxies.containsKey('GLOBAL'), true);
      expect(proxies.containsKey('节点选择'), true);
      expect(proxies.containsKey('自动选择'), true);
      expect(proxies.containsKey('故障转移'), true);
      expect(proxies.containsKey('流媒体'), true);
      expect(proxies.containsKey('AI 服务'), true);
    });

    test('节点选择 has correct type and nodes', () {
      final data = mock.getProxies();
      final group = data['proxies']['节点选择'] as Map<String, dynamic>;

      expect(group['type'], 'Selector');
      expect((group['all'] as List).length, 12);
      expect(group['now'], isA<String>());
    });

    test('故障转移 has subset of nodes', () {
      final data = mock.getProxies();
      final group = data['proxies']['故障转移'] as Map<String, dynamic>;

      expect(group['type'], 'Fallback');
      expect((group['all'] as List).length, 5);
    });

    test('changeProxy on non-tracked group returns true', () {
      final ok = mock.changeProxy('流媒体', '🇭🇰 香港 01');
      expect(ok, true);
    });

    test('delay varies by region', () {
      // Test multiple times to check ranges
      final hkDelays = List.generate(10, (_) => mock.testDelay('🇭🇰 香港 01'));
      final usDelays = List.generate(10, (_) => mock.testDelay('🇺🇸 美国 01'));

      // HK should generally be faster than US
      final avgHk = hkDelays.reduce((a, b) => a + b) / hkDelays.length;
      final avgUs = usDelays.reduce((a, b) => a + b) / usDelays.length;
      expect(avgHk, lessThan(avgUs));
    });
  });

  group('CoreMock connections', () {
    test('returns mock connections with expected fields', () {
      final data = mock.getConnections();
      final conns = data['connections'] as List;

      expect(conns.length, 5);

      final first = conns[0] as Map<String, dynamic>;
      expect(first.containsKey('id'), true);
      expect(first.containsKey('metadata'), true);
      expect(first.containsKey('rule'), true);
      expect(first.containsKey('chains'), true);
      expect(first.containsKey('upload'), true);
      expect(first.containsKey('download'), true);
      expect(first.containsKey('start'), true);
    });

    test('closeConnection returns true', () {
      expect(mock.closeConnection('any-id'), true);
    });

    test('connections have valid metadata', () {
      final data = mock.getConnections();
      final conns = data['connections'] as List;

      for (final conn in conns) {
        final meta =
            (conn as Map<String, dynamic>)['metadata'] as Map<String, dynamic>;
        expect(meta.containsKey('host'), true);
        expect(meta.containsKey('network'), true);
        expect(meta['network'], anyOf('tcp', 'udp'));
      }
    });
  });
}
