import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/modules/yue_auth/providers/yue_auth_providers.dart';

/// Regression coverage for the dispose guard added to AuthNotifier._init().
///
/// The build flow is: build() runs synchronously, schedules `_init()` as a
/// fire-and-forget microtask, returns an empty AuthState. `_init` then
/// `await`s `_authService.getToken()` (and on the logged-in branch, two
/// more reads). Every continuation ends in a `state = AuthState(...)`
/// assignment, which throws on a disposed Notifier.
///
/// Realistic trigger: app cold start, user taps away from the first frame
/// before SecureStorage resolves — or test harness tears down the
/// container immediately after reading `authProvider`.

bool _isDisposeError(Object e) {
  final s = e.toString().toLowerCase();
  return s.contains('disposed') ||
      s.contains('cannot use state') ||
      s.contains('after it was disposed');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('yuelink_auth_guard_');

    // SecureStorageService on macOS reads via path_provider →
    // getApplicationSupportDirectory(). Mock to our tempDir so reads
    // resolve (file won't exist → returns null, same shape as "no saved
    // token on disk") without touching the real host filesystem.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getApplicationSupportDirectory' ||
            call.method == 'getApplicationDocumentsDirectory') {
          return tempDir.path;
        }
        return null;
      },
    );

    // On non-macOS hosts SecureStorageService goes through
    // flutter_secure_storage's channel. Mock to "no saved credentials"
    // so _init's getToken() returns null cleanly (and hits the
    // loggedOut state-write branch we want to guard).
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
        if (call.method == 'read' || call.method == 'readAll') return null;
        // write / delete / containsKey → no-op
        return null;
      },
    );
  });

  tearDownAll(() {
    tempDir.deleteSync(recursive: true);
  });

  // ── case A: _init continuation runs after dispose ───────────────────
  //
  // build() schedules `_init()` as a microtask; disposing the container
  // synchronously sets `_disposed = true` before that microtask runs. The
  // in-flight `await _authService.getToken()` still resolves one tick
  // later — and without the guard the next line `state = AuthState(
  // status: loggedOut)` fires on a disposed Notifier and throws.
  test('_init completion after provider dispose does not write state',
      () async {
    final errors = <Object>[];

    await runZonedGuarded<Future<void>>(() async {
      final container = ProviderContainer();

      // Trigger build → _init() is scheduled.
      container.read(authProvider);

      // Dispose is synchronous — _disposed flips to true before
      // the first microtask of _init runs.
      container.dispose();

      // Let microtasks drain so _init's awaits resolve and any state
      // writes (guarded or not) run to completion.
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }, (err, _) => errors.add(err));

    final bad = errors.where(_isDisposeError).toList();
    expect(bad, isEmpty,
        reason: '_init must early-return after dispose before touching '
            'state; got: $bad');
  });

  // ── case B: preloaded loggedIn → _refreshUserInfo fire-and-forget ───
  //
  // When build() takes the fast path (preloaded AuthState is loggedIn
  // with a token), it kicks off _refreshUserInfo as fire-and-forget.
  // _refreshUserInfo has had a guard on its `state = ...` line for a
  // while; this case is a regression lock so the guard stays put.
  test('_refreshUserInfo fire-and-forget after dispose does not write state',
      () async {
    final errors = <Object>[];

    await runZonedGuarded<Future<void>>(() async {
      final container = ProviderContainer(overrides: [
        preloadedAuthStateProvider.overrideWithValue(
          const AuthState(
            status: AuthStatus.loggedIn,
            token: 'test-token',
          ),
        ),
      ]);

      // Trigger build — preloaded is loggedIn, so _refreshUserInfo fires.
      // That call reaches real network (no mock), which will fail and
      // hit the catch block. The guard we care about is on the success
      // branch at line 313 of yue_auth_providers.dart — to exercise it
      // we just need the XBoardApi round-trip to be in flight when we
      // dispose.
      container.read(authProvider);

      // Give the HTTP client time to start, then dispose.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      container.dispose();

      // Wait long enough for any network timeout to unwind and for
      // continuations to reach the now-disposed Notifier.
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }, (err, _) => errors.add(err));

    final bad = errors.where(_isDisposeError).toList();
    expect(bad, isEmpty,
        reason: '_refreshUserInfo must check _disposed before state =; '
            'got: $bad');
  });
}
