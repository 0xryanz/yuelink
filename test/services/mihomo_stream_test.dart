import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/services/mihomo_stream.dart';

void main() {
  group('LogEntry', () {
    test('creates with current timestamp by default', () {
      final entry = LogEntry(type: 'info', payload: 'test message');
      expect(entry.type, 'info');
      expect(entry.payload, 'test message');
      expect(entry.timestamp.difference(DateTime.now()).inSeconds.abs(), lessThan(2));
    });

    test('creates with custom timestamp', () {
      final ts = DateTime(2025, 1, 1, 12, 0, 0);
      final entry = LogEntry(type: 'error', payload: 'fail', timestamp: ts);
      expect(entry.timestamp, ts);
    });
  });

  group('MihomoStream', () {
    test('default configuration', () {
      final stream = MihomoStream();
      expect(stream.host, '127.0.0.1');
      expect(stream.port, 9090);
      expect(stream.secret, isNull);
    });

    test('custom configuration', () {
      final stream =
          MihomoStream(host: '10.0.0.1', port: 9091, secret: 'abc');
      expect(stream.host, '10.0.0.1');
      expect(stream.port, 9091);
      expect(stream.secret, 'abc');
    });
  });
}
