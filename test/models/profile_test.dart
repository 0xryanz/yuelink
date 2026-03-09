import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/models/profile.dart';
import 'package:yuelink/services/subscription_parser.dart';

void main() {
  group('Profile', () {
    test('serializes to JSON and back', () {
      final profile = Profile(
        id: '123',
        name: 'Test Airport',
        url: 'https://example.com/sub',
        lastUpdated: DateTime(2026, 1, 15, 10, 30),
        updateInterval: const Duration(hours: 12),
        subInfo: const SubscriptionInfo(
          upload: 1000000,
          download: 5000000,
          total: 100000000000,
          expire: null,
        ),
      );

      final json = profile.toJson();
      final restored = Profile.fromJson(json);

      expect(restored.id, '123');
      expect(restored.name, 'Test Airport');
      expect(restored.url, 'https://example.com/sub');
      expect(restored.updateInterval.inHours, 12);
      expect(restored.subInfo?.upload, 1000000);
      expect(restored.subInfo?.download, 5000000);
      expect(restored.subInfo?.total, 100000000000);
    });

    test('fromJson with minimal data', () {
      final profile = Profile.fromJson({
        'id': '1',
        'name': 'Minimal',
        'url': 'https://example.com',
      });

      expect(profile.id, '1');
      expect(profile.name, 'Minimal');
      expect(profile.lastUpdated, isNull);
      expect(profile.subInfo, isNull);
      expect(profile.updateInterval.inHours, 24); // default
    });

    test('hasSubInfo', () {
      final withInfo = Profile(
        id: '1',
        name: 'A',
        url: '',
        subInfo: const SubscriptionInfo(total: 100),
      );
      final withoutInfo = Profile(id: '2', name: 'B', url: '');
      final withNullTotal = Profile(
        id: '3',
        name: 'C',
        url: '',
        subInfo: const SubscriptionInfo(),
      );

      expect(withInfo.hasSubInfo, true);
      expect(withoutInfo.hasSubInfo, false);
      expect(withNullTotal.hasSubInfo, false);
    });
  });
}
