import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/auth_token_service.dart';
import '../../../core/storage/settings_service.dart';
import '../../../infrastructure/datasources/xboard/index.dart';
// Re-export shared types so other modules import from auth, not datasources.
export '../../../infrastructure/datasources/xboard/index.dart'
    show XBoardApi, XBoardApiException, UserProfile, SubscribeData;
import '../../../i18n/app_strings.dart';
import '../../../modules/profiles/providers/profiles_providers.dart';
import '../../../domain/models/profile.dart' show ProfileSource;
import '../../../core/kernel/core_manager.dart';
import '../../../core/kernel/recovery_manager.dart';
import '../../../infrastructure/repositories/profile_repository.dart';
import '../../../shared/app_notifier.dart';
import '../../../shared/event_log.dart';
import '../../../shared/telemetry.dart';

// ------------------------------------------------------------------
// Auth state
// ------------------------------------------------------------------

enum AuthStatus { unknown, loggedOut, loggedIn, guest }

class AuthState {
  final AuthStatus status;
  final String? token;
  final UserProfile? userProfile;
  final String? error;
  final bool isLoading;

  const AuthState({
    this.status = AuthStatus.unknown,
    this.token,
    this.userProfile,
    this.error,
    this.isLoading = false,
  });

  /// Copy with nullable field support. Pass [_clearToken] or [_clearProfile]
  /// as `true` to explicitly null out the field (since `null` means "keep").
  AuthState copyWith({
    AuthStatus? status,
    String? token,
    bool clearToken = false,
    UserProfile? userProfile,
    bool clearProfile = false,
    String? error,
    bool? isLoading,
  }) {
    return AuthState(
      status: status ?? this.status,
      token: clearToken ? null : (token ?? this.token),
      userProfile: clearProfile ? null : (userProfile ?? this.userProfile),
      error: error,
      isLoading: isLoading ?? this.isLoading,
    );
  }

  bool get isLoggedIn => status == AuthStatus.loggedIn && token != null;
  bool get isGuest => status == AuthStatus.guest;
}

// ------------------------------------------------------------------
// XBoard API provider
// ------------------------------------------------------------------

/// Default XBoard panel URL — override via AuthTokenService.saveApiHost().
/// Uses yue.yuebao.website (direct to 23.80.91.14) as primary — most reliable
/// for API calls from China. CloudFront (yuetong.app) is better for web browsers
/// but less stable for native app API calls in some Chinese ISPs.
const _kDefaultApiHost = 'https://yue.yuebao.website';

/// CloudFront CDN fallback — used when the direct origin is unreachable.
const String? _kDirectOriginUrl = 'https://yuetong.app';

/// Tracks the current API host — updated on login and restored from storage.
final _apiHostProvider = StateProvider<String>((ref) => _kDefaultApiHost);

final xboardApiProvider = Provider<XBoardApi>((ref) {
  final host = ref.watch(_apiHostProvider);
  return XBoardApi(baseUrl: host, fallbackUrl: _kDirectOriginUrl);
});

// ------------------------------------------------------------------
// Auth notifier
// ------------------------------------------------------------------

/// Pre-loaded auth state, overridden in main.dart ProviderScope to
/// eliminate the blank screen from async AuthNotifier._init().
final preloadedAuthStateProvider = Provider<AuthState?>((ref) => null);

final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);

class AuthNotifier extends Notifier<AuthState> {
  late final AuthTokenService _authService;
  bool _disposed = false;

  @override
  AuthState build() {
    _disposed = false;
    _authService = AuthTokenService.instance;
    ref.onDispose(() => _disposed = true);

    final initial = ref.read(preloadedAuthStateProvider);
    if (initial != null && initial.status != AuthStatus.unknown) {
      // Pre-loaded in main() — skip async _init(), just refresh in background
      if (initial.token != null) _refreshUserInfo(initial.token!);
      return initial;
    }
    _init();
    return const AuthState();
  }

  /// Check if user has a saved token on app startup.
  ///
  /// Fire-and-forget from build(). Each `await` below returns into a
  /// `state = ...` assignment; on a disposed Notifier that throws. The
  /// guard pattern here is the same as in checkin_provider: check
  /// `_disposed` after every await and bail out before touching state
  /// (or any other provider's state). Also covers the `_apiHostProvider`
  /// write so a dispose-after-token doesn't reach through into unrelated
  /// providers.
  Future<void> _init() async {
    final token = await _authService.getToken();
    if (_disposed) return;
    if (token != null && token.isNotEmpty) {
      // Restore saved API host so all providers use the correct endpoint
      final savedHost = await _authService.getApiHost();
      if (_disposed) return;
      if (savedHost != null && savedHost.isNotEmpty) {
        ref.read(_apiHostProvider.notifier).state = savedHost;
      }
      final cachedProfile = await _authService.getCachedProfile();
      if (_disposed) return;
      state = AuthState(
        status: AuthStatus.loggedIn,
        token: token,
        userProfile: cachedProfile,
      );
      // Refresh user info in background
      _refreshUserInfo(token);
    } else {
      state = const AuthState(status: AuthStatus.loggedOut);
    }
  }

  /// Login with email and password.
  Future<bool> login(String email, String password, {String? apiHost}) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      // Resolve API host
      final host = apiHost ?? _kDefaultApiHost;
      final api = XBoardApi(baseUrl: host, fallbackUrl: _kDirectOriginUrl);

      // 1. Login
      final loginResp = await api.login(email, password);
      final token = loginResp.token;

      // 2. Save token and host, update provider so all consumers get correct host
      await _authService.saveToken(token);
      await _authService.saveApiHost(host);
      ref.read(_apiHostProvider.notifier).state = host;
      EventLog.write('[Auth] login_ok');

      // 3. Get subscribe data (profile + URL) in one request.
      //    /api/v1/user/getSubscribe returns plan name, u/d traffic, expiry, subscribe_url.
      //    /api/v1/user/info does NOT return u/d or nested plan object — do not use it.
      UserProfile? profile;
      try {
        final sub = await api.getSubscribeData(token);
        profile = sub.profile;
        await _authService.cacheProfile(profile);
        await _authService.saveSubscribeUrl(sub.subscribeUrl);
        _syncSubscription(sub.subscribeUrl).catchError((e) {
          debugPrint('[Auth] Background sync failed: $e');
        });
      } catch (e) {
        debugPrint('[Auth] Failed to fetch subscribe data: $e');
      }

      state = AuthState(
        status: AuthStatus.loggedIn,
        token: token,
        userProfile: profile,
      );
      Telemetry.event(TelemetryEvents.loginSuccess);

      // If profile fetch failed during login, retry in background so the
      // dashboard doesn't stay stuck on "暂无订阅".
      if (profile == null) {
        _refreshUserInfo(token);
      }

      return true;
    } on XBoardApiException catch (e) {
      EventLog.write('[Auth] login_fail status=${e.statusCode}');
      Telemetry.event(
        TelemetryEvents.loginFailed,
        priority: true,
        props: {'status': e.statusCode},
      );
      state = state.copyWith(
        isLoading: false,
        error: _friendlyLoginError(e),
      );
      return false;
    } catch (e) {
      EventLog.write('[Auth] login_fail error=${e.runtimeType}');
      Telemetry.event(
        TelemetryEvents.loginFailed,
        priority: true,
        props: {'error': e.runtimeType.toString()},
      );
      state = state.copyWith(
        isLoading: false,
        error: _friendlyNetworkError(e),
      );
      return false;
    }
  }

  /// Maps API/network exceptions to user-friendly login error messages.
  static String _friendlyLoginError(XBoardApiException e) {
    if (e.statusCode == 401 || e.statusCode == 422 || e.statusCode == 400) {
      // Check if server sent a readable message (XBoard often does)
      final msg = e.message;
      if (msg.isNotEmpty && msg.length < 80 && !msg.startsWith('{')) return msg;
      return S.current.authErrorBadCredentials;
    }
    if (e.statusCode >= 500) return S.current.authErrorServer;
    if (e.statusCode == 0) return S.current.authErrorNetwork;
    final msg = e.message;
    if (msg.isNotEmpty && msg.length < 80) return msg;
    return S.current.authErrorServer;
  }

  static String _friendlyNetworkError(dynamic e) {
    final s = e.toString();
    if (s.contains('SocketException') ||
        s.contains('HandshakeException') ||
        s.contains('TimeoutException') ||
        s.contains('NetworkException')) {
      return S.current.authErrorNetwork;
    }
    return S.current.authErrorNetwork;
  }

  /// Enter guest mode (skip login). User can import profiles manually.
  void skipLogin() {
    state = const AuthState(status: AuthStatus.guest);
  }

  /// Logout and clear all auth data, profiles, and stop VPN.
  Future<void> logout() async {
    Telemetry.event(TelemetryEvents.logout);
    // Stop running VPN/core and reset all Riverpod state before clearing data.
    // Must use resetCoreToStopped (not CoreManager.stop() directly) so that
    // coreStatusProvider, trafficProvider, historyProvider, etc. are cleared.
    // Otherwise re-login shows stale "Connected" status for up to 30 seconds.
    try {
      resetCoreToStopped(ref, clearDesktopProxy: true);
    } catch (e) {
      debugPrint('[Auth] stop core on logout failed: $e');
    }

    // Clear ONLY profiles synced from this account (source == account).
    // User-imported profiles (source == manual) survive logout to prevent
    // data loss. Legacy profiles created before the `source` field existed
    // default to manual and are also preserved.
    try {
      final repo = ref.read(profileRepositoryProvider);
      final profiles = await repo.loadProfiles();
      var deleted = 0;
      var preserved = 0;
      for (final p in profiles) {
        if (p.isAccountManaged) {
          await repo.deleteProfile(p.id);
          deleted++;
        } else {
          preserved++;
        }
      }
      debugPrint(
          '[Auth] logout: deleted $deleted account profile(s), preserved $preserved manual profile(s)');
    } catch (e) {
      debugPrint('[Auth] clear profiles on logout failed: $e');
    }

    await _authService.clearAll();
    state = const AuthState(status: AuthStatus.loggedOut);
  }

  /// Called when any API returns 401/403. Shows a toast and logs out.
  /// Call this from any provider that detects token expiry.
  Future<void> handleUnauthenticated() async {
    if (state.status != AuthStatus.loggedIn) return; // already logged out
    EventLog.write('[Auth] session_expired auto_logout');
    AppNotifier.warning(S.current.authSessionExpired);
    await logout();
  }

  /// Refresh user info from server.
  Future<void> refreshUserInfo() async {
    final token = state.token;
    if (token == null) return;
    await _refreshUserInfo(token);
  }

  Future<void> _refreshUserInfo(String token) async {
    try {
      final host = await _authService.getApiHost() ?? _kDefaultApiHost;
      final api = XBoardApi(baseUrl: host, fallbackUrl: _kDirectOriginUrl);
      final sub = await api.getSubscribeData(token);
      await _authService.cacheProfile(sub.profile);
      // Also update subscribe URL in case it changed
      await _authService.saveSubscribeUrl(sub.subscribeUrl);
      if (!_disposed) {
        state = state.copyWith(userProfile: sub.profile);
      }
    } catch (e) {
      debugPrint('[Auth] Failed to refresh user info: $e');
      if (e is XBoardApiException && (e.statusCode == 401 || e.statusCode == 403)) {
        await handleUnauthenticated();
      }
    }
  }

  /// Sync subscription: refresh profile data and download proxy config.
  Future<void> syncSubscription() async {
    final token = state.token;
    if (token == null) return;
    try {
      final host = await _authService.getApiHost() ?? _kDefaultApiHost;
      final api = XBoardApi(baseUrl: host, fallbackUrl: _kDirectOriginUrl);
      // Always fetch fresh from server — also updates profile data
      final sub = await api.getSubscribeData(token);
      await _authService.cacheProfile(sub.profile);
      await _authService.saveSubscribeUrl(sub.subscribeUrl);
      if (!_disposed) state = state.copyWith(userProfile: sub.profile);
      await _syncSubscription(sub.subscribeUrl);
      Telemetry.event(TelemetryEvents.subscriptionSync);
    } catch (e) {
      debugPrint('[Auth] Failed to sync subscription: $e');
      if (e is XBoardApiException && (e.statusCode == 401 || e.statusCode == 403)) {
        await handleUnauthenticated();
        return; // after logout, don't rethrow
      }
      rethrow;
    }
  }

  /// Internal: download and save subscription config.
  ///
  /// The subscribe URL is served only by the SSO nginx rewrite; other hosts
  /// are rejected by XBoard's SubscriptionRiskControl with a 403 HTML page.
  /// Host-rewrite fallback would corrupt the config, not recover it — so
  /// there is no retry loop here. If the primary URL fails, surface the
  /// real error.
  Future<void> _syncSubscription(String subscribeUrl) async {
    assert(() { debugPrint('[Auth] Syncing subscription from: ${subscribeUrl.substring(0, subscribeUrl.length.clamp(0, 50))}...'); return true; }());

    // Use ProfileRepository for consistent config processing.
    // Check if we already have a "悦通" profile — update it instead of adding.
    final repo = ref.read(profileRepositoryProvider);
    final profiles = await repo.loadProfiles();
    final existing = profiles.where((p) => p.name == '悦通').toList();
    final isFirstTime = existing.isEmpty;

    final proxyPort = CoreManager.instance.isRunning
        ? CoreManager.instance.mixedPort
        : null;

    if (existing.isNotEmpty) {
      // Update existing profile and tag it as account-managed so logout
      // knows it's safe to delete (it'll be recreated on next login).
      final profile = existing.first;
      profile.url = subscribeUrl;
      profile.source = ProfileSource.account;
      await repo.updateProfile(profile, proxyPort: proxyPort);
      debugPrint('[Auth] Updated existing 悦通 profile: ${profile.id}');
    } else {
      // Create new profile, marked as account-managed.
      final profile = await repo.addProfile(
        name: '悦通',
        url: subscribeUrl,
        proxyPort: proxyPort,
        source: ProfileSource.account,
      );
      debugPrint('[Auth] Created new 悦通 profile: ${profile.id}');
      // Auto-select the new profile
      ref.read(activeProfileIdProvider.notifier).select(profile.id);
    }

    // Refresh profiles list in UI
    ref.read(profilesProvider.notifier).load();

    // First-time sync: welcome the user
    if (isFirstTime) {
      EventLog.write('[Sync] sync_ok first_time=true');
      AppNotifier.success(S.current.syncFirstSuccess);
    } else {
      EventLog.write('[Sync] sync_ok update=true');
    }

    // Fire subscription alerts — per-day deduped to avoid toast spam.
    // SubscriptionInfo parses expire / usage from the HTTP header on every
    // sync, but nothing was ever consuming it. Mainstream clients (CVR /
    // FlClash / mihomo-party) all surface near-expiry / near-quota warnings
    // because the user otherwise doesn't find out until the VPN silently
    // stops working.
    await _maybeFireSubscriptionAlerts();
  }

  /// Warn the user if the active profile's subscription is about to expire
  /// or hit its traffic quota. Thresholds:
  ///   - already expired           → error
  ///   - ≤ 3 days until expiry     → warning
  ///   - ≥ 90 % quota consumed     → warning
  /// Deduped per calendar day via `SettingsService.lastSubscriptionAlertKey`
  /// so a 6-hour auto-sync doesn't spam the same toast repeatedly.
  Future<void> _maybeFireSubscriptionAlerts() async {
    try {
      final repo = ref.read(profileRepositoryProvider);
      final profiles = await repo.loadProfiles();
      final profile =
          profiles.where((p) => p.name == '悦通').firstOrNull;
      if (profile == null) return;
      final info = profile.subInfo;
      if (info == null) return; // panel didn't send subscription-userinfo header

      final alerts = <String>[];
      String? alertKey; // same-day dedup key per alert category

      if (info.isExpired) {
        alerts.add('订阅已过期，请尽快续费');
        alertKey = 'expired';
      } else if (info.daysRemaining != null && info.daysRemaining! <= 3) {
        alerts.add('订阅将在 ${info.daysRemaining} 天后到期');
        alertKey = 'expiry_soon';
      }

      final pct = info.usagePercent;
      if (pct != null && pct >= 0.9) {
        alerts.add('流量已使用 ${(pct * 100).toStringAsFixed(0)}%');
        alertKey = alertKey == null ? 'quota_low' : '${alertKey}_quota_low';
      }

      if (alerts.isEmpty) return;

      final today = DateTime.now().toUtc().toIso8601String().substring(0, 10);
      final lastKey = '$today:$alertKey';
      final last = await SettingsService.get<String>('lastSubscriptionAlert');
      if (last == lastKey) return; // already shown today for this category

      final message = alerts.join('；');
      if (info.isExpired) {
        AppNotifier.error(message);
      } else {
        AppNotifier.warning(message);
      }
      EventLog.write('[Sync] subscription_alert: $message');
      await SettingsService.set('lastSubscriptionAlert', lastKey);
    } catch (e) {
      debugPrint('[Auth] subscription alert check threw: $e');
    }
  }
}

// ------------------------------------------------------------------
// Convenience providers
// ------------------------------------------------------------------

/// Current user profile (may be null if not logged in or not yet fetched).
final userProfileProvider = Provider<UserProfile?>((ref) {
  return ref.watch(authProvider).userProfile;
});
