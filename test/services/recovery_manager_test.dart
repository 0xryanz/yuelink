import 'package:flutter_test/flutter_test.dart';
import 'package:yuelink/core/kernel/recovery_manager.dart';

void main() {
  group('RecoveryManager.isAliveForPlatform', () {
    test('android trusts API availability over FFI running flag', () {
      expect(
        RecoveryManager.isAliveForPlatform(
          apiOk: true,
          ffiRunning: false,
          isAndroid: true,
          isIOS: false,
        ),
        isTrue,
      );
      expect(
        RecoveryManager.isAliveForPlatform(
          apiOk: false,
          ffiRunning: true,
          isAndroid: true,
          isIOS: false,
        ),
        isFalse,
      );
    });

    test('ios trusts API availability over FFI running flag', () {
      expect(
        RecoveryManager.isAliveForPlatform(
          apiOk: true,
          ffiRunning: false,
          isAndroid: false,
          isIOS: true,
        ),
        isTrue,
      );
    });

    test('desktop requires both API and FFI health', () {
      expect(
        RecoveryManager.isAliveForPlatform(
          apiOk: true,
          ffiRunning: true,
          isAndroid: false,
          isIOS: false,
        ),
        isTrue,
      );
      expect(
        RecoveryManager.isAliveForPlatform(
          apiOk: true,
          ffiRunning: false,
          isAndroid: false,
          isIOS: false,
        ),
        isFalse,
      );
      expect(
        RecoveryManager.isAliveForPlatform(
          apiOk: false,
          ffiRunning: true,
          isAndroid: false,
          isIOS: false,
        ),
        isFalse,
      );
    });
  });
}
