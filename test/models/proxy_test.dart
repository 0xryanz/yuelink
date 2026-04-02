import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/domain/models/proxy.dart';

void main() {
  group('ProxyNode', () {
    test('fromJson', () {
      final node = ProxyNode.fromJson({
        'name': 'HK 01',
        'type': 'vmess',
        'delay': 85,
        'alive': true,
      });

      expect(node.name, 'HK 01');
      expect(node.type, 'vmess');
      expect(node.delay, 85);
      expect(node.alive, true);
    });

    test('fromJson with defaults', () {
      final node = ProxyNode.fromJson({
        'name': 'US 01',
        'type': 'ss',
      });

      expect(node.delay, isNull);
      expect(node.alive, true);
    });
  });

  group('ProxyGroup', () {
    test('fromJson', () {
      final group = ProxyGroup.fromJson({
        'name': 'Proxy',
        'type': 'Selector',
        'all': ['HK 01', 'JP 01', 'US 01'],
        'now': 'HK 01',
      });

      expect(group.name, 'Proxy');
      expect(group.type, 'Selector');
      expect(group.all.length, 3);
      expect(group.now, 'HK 01');
    });

    test('fromJson with empty all', () {
      final group = ProxyGroup.fromJson({
        'name': 'Empty',
        'type': 'Fallback',
      });

      expect(group.all, isEmpty);
      expect(group.now, '');
    });
  });
}
