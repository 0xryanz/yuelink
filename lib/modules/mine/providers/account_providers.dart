import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/account/account_overview.dart';
import '../../../domain/account/notice.dart';
import '../../../domain/announcements/announcement_entity.dart';
import '../../../infrastructure/account/account_repository.dart';
import '../../announcements/providers/announcements_providers.dart';
import '../../yue_auth/providers/yue_auth_providers.dart';

// ── DI ───────────────────────────────────────────────────────────────────────

final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  final proxyPort = ref.watch(businessProxyPortProvider);
  return AccountRepository(proxyPort: proxyPort);
});

// ── Providers ─────────────────────────────────────────────────────────────────

/// 账户总览数据（需要 token，用户未登录时返回 null）。
final accountOverviewProvider = FutureProvider<AccountOverview?>((ref) async {
  final token = ref.watch(authProvider.select((s) => s.token));
  if (token == null) return null;
  final repo = ref.read(accountRepositoryProvider);
  return repo.getAccountOverview(token);
});

/// 用户通知列表（需要 token，未登录时返回空列表）。
final accountNoticesProvider = FutureProvider<List<AccountNotice>>((ref) async {
  final token = ref.watch(authProvider.select((s) => s.token));
  if (token == null) return [];
  final repo = ref.read(accountRepositoryProvider);
  return repo.getNotices(token);
});

/// Dashboard notices prefer the dedicated account notices endpoint, but
/// gracefully fall back to XBoard announcements when that sidecar service is
/// empty or temporarily unavailable.
final dashboardNoticesProvider =
    FutureProvider<List<AccountNotice>>((ref) async {
  final token = ref.watch(authProvider.select((s) => s.token));
  if (token == null) return [];

  final notices = await ref.watch(accountNoticesProvider.future);
  if (notices.isNotEmpty) return notices;

  final repo = ref.read(announcementsRepositoryProvider);
  try {
    final announcements = await repo.getAnnouncements(token);
    return announcements.map(_mapAnnouncementToNotice).toList();
  } on XBoardApiException catch (e) {
    if (e.statusCode == 401 || e.statusCode == 403) {
      await ref.read(authProvider.notifier).handleUnauthenticated();
    }
    return [];
  } catch (_) {
    return [];
  }
});

AccountNotice _mapAnnouncementToNotice(Announcement announcement) {
  return AccountNotice(
    title: announcement.title,
    content: announcement.content,
    createdAt: announcement.createdDate?.toIso8601String(),
  );
}
