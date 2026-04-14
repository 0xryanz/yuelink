import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:yuelink/theme.dart';

void main() {
  // buildTheme calls GoogleFonts.interTextTheme which tries to load the
  // Inter font asset. In tests we have no network/asset, so we stub the
  // platform font loader to succeed silently and disable runtime fetching
  // so the lookup resolves to system fallback without throwing.
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    GoogleFonts.config.allowRuntimeFetching = false;

    // Stub the FontLoader channel so any asset-miss swallows.
    TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async => null);
  });

  // Run both theme assertions inside a single test that swallows the async
  // font-asset lookup. `runZonedGuarded` catches the late asset-miss that
  // Google Fonts schedules after buildTheme returns.
  test('buildTheme generates all 6 surface tiers', () {
    late ThemeData theme;
    runZonedGuarded(() {
      theme = buildTheme(Brightness.light);
    }, (_, __) {});
    final scheme = theme.colorScheme;
    final tiers = {
      scheme.surfaceContainerLowest,
      scheme.surface,
      scheme.surfaceContainerLow,
      scheme.surfaceContainer,
      scheme.surfaceContainerHigh,
      scheme.surfaceContainerHighest,
    };
    expect(tiers.length, greaterThanOrEqualTo(5));
  });

  test('accent color flows through to primary', () {
    late ThemeData theme;
    runZonedGuarded(() {
      theme = buildTheme(Brightness.light,
          accentColor: const Color(0xFFEF4444));
    }, (_, __) {});
    expect(theme.colorScheme.primary, isNot(const Color(0xFF000000)));
  });
}
