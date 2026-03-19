import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/services/config_template.dart';

void main() {
  group('ConfigTemplate.process', () {
    test('replaces \$app_name with YueLink', () {
      const config = 'name: \$app_name\nproxies: []';
      final result = ConfigTemplate.process(config);
      expect(result, contains('name: YueLink'));
      expect(result, isNot(contains('\$app_name')));
    });

    test('adds external-controller when missing', () {
      const config = 'mixed-port: 7890';
      final result = ConfigTemplate.process(config, apiPort: 9090);
      expect(result, contains('external-controller: 127.0.0.1:9090'));
    });

    test('replaces existing external-controller port', () {
      const config = 'external-controller: 0.0.0.0:1234\nmixed-port: 7890';
      final result = ConfigTemplate.process(config, apiPort: 9090);
      expect(result, contains('external-controller: 127.0.0.1:9090'));
      expect(result, isNot(contains(':1234')));
    });

    test('adds secret when provided', () {
      const config = 'mixed-port: 7890';
      final result = ConfigTemplate.process(config, secret: 'mytoken');
      expect(result, contains('secret: mytoken'));
    });
  });

  group('ConfigTemplate extraction', () {
    test('getMixedPort extracts port from config', () {
      expect(ConfigTemplate.getMixedPort('mixed-port: 7890'), 7890);
      expect(ConfigTemplate.getMixedPort('mixed-port: 1080'), 1080);
    });

    test('getMixedPort returns default when missing', () {
      expect(ConfigTemplate.getMixedPort('other: value'), 7890);
    });

    test('getApiPort extracts port', () {
      expect(
        ConfigTemplate.getApiPort('external-controller: 127.0.0.1:9090'),
        9090,
      );
      expect(
        ConfigTemplate.getApiPort('external-controller: :8080'),
        8080,
      );
    });

    test('getSecret extracts secret', () {
      expect(ConfigTemplate.getSecret('secret: abc123'), 'abc123');
      expect(ConfigTemplate.getSecret('secret: "quoted"'), 'quoted');
    });

    test('getSecret returns null when missing', () {
      expect(ConfigTemplate.getSecret('mixed-port: 7890'), isNull);
    });
  });

  group('ConfigTemplate.mergeIfNeeded', () {
    test('uses subscription config directly if it has proxy-groups and rules',
        () {
      const template = 'mixed-port: 7890\nproxies:\n';
      const sub = 'proxies:\n  - name: test\nproxy-groups:\n  - name: g\nrules:\n  - MATCH,DIRECT';
      final result = ConfigTemplate.mergeIfNeeded(template, sub);
      expect(result, equals(sub));
    });

    test('adds mode: rule when missing', () {
      const config = 'mixed-port: 7890\ndns:\n  enable: true';
      final result = ConfigTemplate.process(config);
      expect(result, contains('mode: rule'));
    });

    test('does not override existing mode', () {
      const config = 'mixed-port: 7890\nmode: global\ndns:\n  enable: true';
      final result = ConfigTemplate.process(config);
      expect(result, contains('mode: global'));
      expect(result, isNot(contains('mode: rule')));
    });

    test('preserves complete subscription config without corruption', () {
      // Simulate a real subscription config structure
      const config = '''
mixed-port: 7890
allow-lan: true
find-process-mode: always
dns:
  enable: true
  enhanced-mode: fake-ip
  respect-rules: true
sniffer:
  enable: true
geodata-mode: true
profile:
  store-selected: true
tcp-concurrent: true
unified-delay: true
global-client-fingerprint: chrome
proxies:
  - {name: node1, type: ss, server: 1.2.3.4, port: 443}
proxy-groups:
  - {name: Proxy, type: select, proxies: [node1]}
rules:
  - MATCH,Proxy
''';
      final result = ConfigTemplate.process(config, apiPort: 9090);
      // Should add external-controller but not duplicate existing keys
      expect(result, contains('external-controller: 127.0.0.1:9090'));
      expect(result, contains('mode: rule'));
      // Existing keys should NOT be duplicated
      expect(
          'dns:'.allMatches(result).length, 1, reason: 'dns should not be duplicated');
      expect('sniffer:'.allMatches(result).length, 1,
          reason: 'sniffer should not be duplicated');
      expect('geodata-mode:'.allMatches(result).length, 1,
          reason: 'geodata-mode should not be duplicated');
      expect('profile:'.allMatches(result).length, 1,
          reason: 'profile should not be duplicated');
      expect('mixed-port:'.allMatches(result).length, 1,
          reason: 'mixed-port should not be duplicated');
      // Proxy structure should be preserved
      expect(result, contains('MATCH,Proxy'));
      expect(result, contains('name: node1'));
    });

    test('merges proxies into template when sub has no groups', () {
      const template =
          'mixed-port: 7890\nproxies:\n\nproxy-groups:\n  - name: g\n';
      const sub = 'proxies:\n  - name: node1\n    type: ss\n';
      final result = ConfigTemplate.mergeIfNeeded(template, sub);
      expect(result, contains('name: node1'));
      expect(result, contains('proxy-groups:'));
    });
  });

  group('ECH injection (_ensureEch via process)', () {
    test('injects ech-opts into block-style trojan proxy', () {
      const config = '''
mixed-port: 7890
proxies:
  - name: node1
    type: trojan
    server: example.com
    port: 443
    password: abc
proxy-groups:
  - name: Proxy
    type: select
    proxies: [node1]
rules:
  - MATCH,Proxy
''';
      final result = ConfigTemplate.process(config);
      expect(result, contains('ech-opts:'));
      expect(result, contains('enable: true'));
      // Original structure preserved
      expect(result, contains('name: node1'));
      expect(result, contains('type: trojan'));
      expect(result, contains('proxy-groups:'));
      expect(result, contains('MATCH,Proxy'));
    });

    test('injects ech-opts into flow-style trojan proxy', () {
      const config = '''
mixed-port: 7890
proxies:
  - {name: node1, type: trojan, server: example.com, port: 443, password: abc}
proxy-groups:
  - {name: Proxy, type: select, proxies: [node1]}
rules:
  - MATCH,Proxy
''';
      final result = ConfigTemplate.process(config);
      expect(result, contains('ech-opts: {enable: true}'));
      // Original structure preserved
      expect(result, contains('name: node1'));
      expect(result, contains('MATCH,Proxy'));
    });

    test('skips non-TLS proxy types (ss)', () {
      const config = '''
mixed-port: 7890
proxies:
  - name: node1
    type: ss
    server: example.com
    port: 443
    cipher: aes-256-gcm
    password: abc
proxy-groups:
  - name: Proxy
    type: select
    proxies: [node1]
rules:
  - MATCH,Proxy
''';
      final result = ConfigTemplate.process(config);
      expect(result, isNot(contains('ech-opts')));
    });

    test('skips proxy with existing ech-opts', () {
      const config = '''
mixed-port: 7890
proxies:
  - name: node1
    type: trojan
    server: example.com
    port: 443
    password: abc
    ech-opts:
      enable: true
proxy-groups:
  - name: Proxy
    type: select
    proxies: [node1]
rules:
  - MATCH,Proxy
''';
      final result = ConfigTemplate.process(config);
      // Should have exactly one ech-opts (the existing one), not two
      expect('ech-opts'.allMatches(result).length, 1,
          reason: 'should not duplicate ech-opts');
    });

    test('skips vless with reality-opts', () {
      const config = '''
mixed-port: 7890
proxies:
  - name: node1
    type: vless
    server: example.com
    port: 443
    uuid: abc
    tls: true
    reality-opts:
      public-key: xyz
proxy-groups:
  - name: Proxy
    type: select
    proxies: [node1]
rules:
  - MATCH,Proxy
''';
      final result = ConfigTemplate.process(config);
      expect(result, isNot(contains('ech-opts')));
    });

    test('skips vmess without tls: true', () {
      const config = '''
mixed-port: 7890
proxies:
  - name: node1
    type: vmess
    server: example.com
    port: 443
    uuid: abc
proxy-groups:
  - name: Proxy
    type: select
    proxies: [node1]
rules:
  - MATCH,Proxy
''';
      final result = ConfigTemplate.process(config);
      expect(result, isNot(contains('ech-opts')));
    });

    test('injects ech-opts into vmess with tls: true', () {
      const config = '''
mixed-port: 7890
proxies:
  - name: node1
    type: vmess
    server: example.com
    port: 443
    uuid: abc
    tls: true
proxy-groups:
  - name: Proxy
    type: select
    proxies: [node1]
rules:
  - MATCH,Proxy
''';
      final result = ConfigTemplate.process(config);
      expect(result, contains('ech-opts:'));
      expect(result, contains('enable: true'));
    });

    test('injects into hysteria2 without requiring tls field', () {
      const config = '''
mixed-port: 7890
proxies:
  - name: node1
    type: hysteria2
    server: example.com
    port: 443
    password: abc
proxy-groups:
  - name: Proxy
    type: select
    proxies: [node1]
rules:
  - MATCH,Proxy
''';
      final result = ConfigTemplate.process(config);
      expect(result, contains('ech-opts:'));
    });

    test('handles mixed proxy types — only injects where appropriate', () {
      const config = '''
mixed-port: 7890
proxies:
  - name: ss-node
    type: ss
    server: 1.2.3.4
    port: 443
    cipher: aes-256-gcm
    password: abc
  - name: trojan-node
    type: trojan
    server: 5.6.7.8
    port: 443
    password: def
  - name: vmess-notls
    type: vmess
    server: 9.0.1.2
    port: 443
    uuid: xyz
proxy-groups:
  - name: Proxy
    type: select
    proxies: [ss-node, trojan-node, vmess-notls]
rules:
  - MATCH,Proxy
''';
      final result = ConfigTemplate.process(config);
      // Only trojan-node should get ech-opts
      expect('ech-opts'.allMatches(result).length, 1,
          reason: 'only trojan should get ech-opts');
      // ss-node and vmess-notls should not
      expect(result, contains('name: ss-node'));
      expect(result, contains('name: vmess-notls'));
    });

    test('does not modify config when all proxies already have ech-opts', () {
      const config = '''
mixed-port: 7890
proxies:
  - name: node1
    type: trojan
    server: example.com
    port: 443
    password: abc
    ech-opts:
      enable: true
  - name: node2
    type: hysteria2
    server: example2.com
    port: 443
    password: def
    ech-opts:
      enable: true
proxy-groups:
  - name: Proxy
    type: select
    proxies: [node1, node2]
rules:
  - MATCH,Proxy
''';
      final result = ConfigTemplate.process(config);
      // Should still have exactly 2 ech-opts (the existing ones)
      expect('ech-opts'.allMatches(result).length, 2,
          reason: 'should not add extra ech-opts');
    });

    test('preserves YAML comments and structure (no re-serialization)', () {
      const config = '''
mixed-port: 7890
# This is a comment that should be preserved
proxies:
  - name: node1 # inline comment
    type: trojan
    server: example.com
    port: 443
    password: abc
proxy-groups:
  - name: Proxy
    type: select
    proxies: [node1]
rules:
  - MATCH,Proxy
''';
      final result = ConfigTemplate.process(config);
      expect(result, contains('# This is a comment that should be preserved'));
      expect(result, contains('# inline comment'));
      expect(result, contains('ech-opts:'));
    });

    test('injects ech-opts into flow-style with existing ech-opts skipped', () {
      const config = '''
mixed-port: 7890
proxies:
  - {name: node1, type: trojan, server: a.com, port: 443, password: abc, ech-opts: {enable: true}}
  - {name: node2, type: trojan, server: b.com, port: 443, password: def}
proxy-groups:
  - {name: Proxy, type: select, proxies: [node1, node2]}
rules:
  - MATCH,Proxy
''';
      final result = ConfigTemplate.process(config);
      // node1 already has ech-opts, node2 should get it
      expect('ech-opts'.allMatches(result).length, 2);
    });

    test('handles empty proxies list', () {
      const config = '''
mixed-port: 7890
proxies:
proxy-groups:
  - name: Proxy
    type: select
rules:
  - MATCH,DIRECT
''';
      final result = ConfigTemplate.process(config);
      expect(result, isNot(contains('ech-opts')));
    });

    test('injects into anytls proxy type', () {
      const config = '''
mixed-port: 7890
proxies:
  - name: node1
    type: anytls
    server: example.com
    port: 443
    password: abc
proxy-groups:
  - name: Proxy
    type: select
    proxies: [node1]
rules:
  - MATCH,Proxy
''';
      final result = ConfigTemplate.process(config);
      expect(result, contains('ech-opts:'));
    });

    test('injects into tuic proxy type', () {
      const config = '''
mixed-port: 7890
proxies:
  - name: node1
    type: tuic
    server: example.com
    port: 443
    uuid: abc
    password: def
proxy-groups:
  - name: Proxy
    type: select
    proxies: [node1]
rules:
  - MATCH,Proxy
''';
      final result = ConfigTemplate.process(config);
      expect(result, contains('ech-opts:'));
    });
  });
}
