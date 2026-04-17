import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/domain/account/notice.dart';
import 'package:yuelink/domain/announcements/announcement_entity.dart';
import 'package:yuelink/infrastructure/account/account_repository.dart';
import 'package:yuelink/infrastructure/announcements/announcements_repository.dart';
import 'package:yuelink/modules/announcements/providers/announcements_providers.dart';
import 'package:yuelink/modules/mine/providers/account_providers.dart';
import 'package:yuelink/modules/yue_auth/providers/yue_auth_providers.dart';

class _FakeAuthNotifier extends AuthNotifier {
  @override
  AuthState build() {
    return const AuthState(
      status: AuthStatus.loggedIn,
      token: 'test-token',
    );
  }
}

class _FakeAccountRepository extends AccountRepository {
  _FakeAccountRepository(this.notices);

  final List<AccountNotice> notices;
  int calls = 0;

  @override
  Future<List<AccountNotice>> getNotices(String token) async {
    calls += 1;
    return notices;
  }
}

class _FakeAnnouncementsRepository extends AnnouncementsRepository {
  _FakeAnnouncementsRepository(this.announcements)
      : super(api: XBoardApi(baseUrl: 'https://example.com'));

  final List<Announcement> announcements;
  int calls = 0;

  @override
  Future<List<Announcement>> getAnnouncements(String token) async {
    calls += 1;
    return announcements;
  }
}

void main() {
  group('dashboardNoticesProvider', () {
    test('prefers account notices when service notices exist', () async {
      final accountRepo = _FakeAccountRepository(const [
        AccountNotice(
          title: 'Service notice',
          content: 'from account service',
          createdAt: '2026-04-18T01:00:00.000Z',
        ),
      ]);
      final announcementsRepo = _FakeAnnouncementsRepository([
        Announcement(
          id: 1,
          title: 'Fallback notice',
          content: 'from xboard',
          createdAt: 1713402000,
        ),
      ]);

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(_FakeAuthNotifier.new),
          accountRepositoryProvider.overrideWithValue(accountRepo),
          announcementsRepositoryProvider.overrideWithValue(announcementsRepo),
        ],
      );
      addTearDown(container.dispose);

      final notices = await container.read(dashboardNoticesProvider.future);

      expect(notices, hasLength(1));
      expect(notices.first.title, 'Service notice');
      expect(accountRepo.calls, 1);
      expect(
        announcementsRepo.calls,
        0,
        reason: 'dashboard should not hit fallback when service notices exist',
      );
    });

    test('falls back to xboard announcements when account notices are empty',
        () async {
      final accountRepo = _FakeAccountRepository(const []);
      final announcementsRepo = _FakeAnnouncementsRepository([
        Announcement(
          id: 2,
          title: 'Panel notice',
          content: 'from fallback source',
          createdAt: 1713402000,
        ),
      ]);

      final container = ProviderContainer(
        overrides: [
          authProvider.overrideWith(_FakeAuthNotifier.new),
          accountRepositoryProvider.overrideWithValue(accountRepo),
          announcementsRepositoryProvider.overrideWithValue(announcementsRepo),
        ],
      );
      addTearDown(container.dispose);

      final notices = await container.read(dashboardNoticesProvider.future);

      expect(notices, hasLength(1));
      expect(notices.first.title, 'Panel notice');
      final expectedCreatedAt =
          DateTime.fromMillisecondsSinceEpoch(1713402000 * 1000)
              .toIso8601String();
      expect(
        notices.first.createdAt,
        expectedCreatedAt,
      );
      expect(accountRepo.calls, 1);
      expect(announcementsRepo.calls, 1);
    });
  });
}
