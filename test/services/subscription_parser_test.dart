import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/services/subscription_parser.dart';

void main() {
  group('SubscriptionInfo', () {
    test('parses standard subscription-userinfo header', () {
      final info = SubscriptionInfo.fromHeaders({
        'subscription-userinfo':
            'upload=1073741824; download=5368709120; total=107374182400; expire=1735689600',
      });

      expect(info.upload, 1073741824); // 1 GB
      expect(info.download, 5368709120); // 5 GB
      expect(info.total, 107374182400); // 100 GB
      expect(info.expire, isNotNull);
      expect(info.expire!.year, 2025);
    });

    test('calculates remaining traffic', () {
      final info = SubscriptionInfo(
        upload: 1000,
        download: 2000,
        total: 10000,
      );

      expect(info.remaining, 7000);
      expect(info.usagePercent, closeTo(0.3, 0.001));
    });

    test('remaining is null when total is null', () {
      const info = SubscriptionInfo(upload: 1000, download: 2000);
      expect(info.remaining, isNull);
      expect(info.usagePercent, isNull);
    });

    test('handles empty header', () {
      final info = SubscriptionInfo.fromHeaders({});

      expect(info.upload, isNull);
      expect(info.download, isNull);
      expect(info.total, isNull);
      expect(info.expire, isNull);
    });

    test('parses update interval from header', () {
      final info = SubscriptionInfo.fromHeaders({
        'subscription-userinfo': 'upload=0; download=0; total=100',
        'profile-update-interval': '12',
      });

      expect(info.updateInterval, 12);
    });

    test('isExpired', () {
      final expired = SubscriptionInfo(
        expire: DateTime.now().subtract(const Duration(days: 1)),
      );
      final notExpired = SubscriptionInfo(
        expire: DateTime.now().add(const Duration(days: 30)),
      );
      const noExpiry = SubscriptionInfo();

      expect(expired.isExpired, true);
      expect(notExpired.isExpired, false);
      expect(noExpiry.isExpired, false);
    });

    test('daysRemaining', () {
      final info = SubscriptionInfo(
        expire: DateTime.now().add(const Duration(days: 15, hours: 12)),
      );

      // Allow +/- 1 due to time-of-day rounding
      expect(info.daysRemaining, greaterThanOrEqualTo(15));
      expect(info.daysRemaining, lessThanOrEqualTo(16));
    });

    test('serializes to JSON and back', () {
      final original = SubscriptionInfo(
        upload: 100,
        download: 200,
        total: 1000,
        expire: DateTime.fromMillisecondsSinceEpoch(1735689600000),
        updateInterval: 24,
      );

      final json = original.toJson();
      final restored = SubscriptionInfo.fromJson(json);

      expect(restored.upload, 100);
      expect(restored.download, 200);
      expect(restored.total, 1000);
      expect(restored.updateInterval, 24);
    });
  });

  group('formatBytes', () {
    test('formats correctly', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(1048576), '1.0 MB');
      expect(formatBytes(1073741824), '1.0 GB');
      expect(formatBytes(1099511627776), '1.0 TB');
    });
  });
}
