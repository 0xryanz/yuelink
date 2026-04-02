import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/domain/models/rule.dart';

void main() {
  group('RuleInfo', () {
    test('fromJson parses correctly', () {
      final rule = RuleInfo.fromJson({
        'type': 'DOMAIN-SUFFIX',
        'payload': 'google.com',
        'proxy': '节点选择',
      });
      expect(rule.type, 'DOMAIN-SUFFIX');
      expect(rule.payload, 'google.com');
      expect(rule.proxy, '节点选择');
      expect(rule.size, 0);
    });

    test('fromJson with size (RULE-SET)', () {
      final rule = RuleInfo.fromJson({
        'type': 'RULE-SET',
        'payload': 'cncidr',
        'proxy': 'DIRECT',
        'size': 8520,
      });
      expect(rule.type, 'RULE-SET');
      expect(rule.size, 8520);
    });

    test('fromJson handles missing fields', () {
      final rule = RuleInfo.fromJson({});
      expect(rule.type, '');
      expect(rule.payload, '');
      expect(rule.proxy, '');
      expect(rule.size, 0);
    });

    test('MATCH rule has empty payload', () {
      final rule = RuleInfo.fromJson({
        'type': 'MATCH',
        'payload': '',
        'proxy': '节点选择',
      });
      expect(rule.type, 'MATCH');
      expect(rule.payload, '');
    });
  });
}
