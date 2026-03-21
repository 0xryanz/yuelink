import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../infrastructure/datasources/xboard_api.dart';
import '../../modules/yue_auth/providers/yue_auth_providers.dart';
import '../../shared/app_notifier.dart';
import '../../l10n/app_strings.dart';
import 'models/checkin_result.dart';
import 'checkin_repository.dart';

// ------------------------------------------------------------------
// Checkin state
// ------------------------------------------------------------------

class CheckinState {
  final bool checkedIn;
  final bool loading;
  final CheckinResult? lastResult;
  final String? error;

  const CheckinState({
    this.checkedIn = false,
    this.loading = false,
    this.lastResult,
    this.error,
  });

  CheckinState copyWith({
    bool? checkedIn,
    bool? loading,
    CheckinResult? lastResult,
    String? error,
  }) =>
      CheckinState(
        checkedIn: checkedIn ?? this.checkedIn,
        loading: loading ?? this.loading,
        lastResult: lastResult ?? this.lastResult,
        error: error,
      );
}

// ------------------------------------------------------------------
// Provider
// ------------------------------------------------------------------

final checkinProvider =
    NotifierProvider<CheckinNotifier, CheckinState>(CheckinNotifier.new);

class CheckinNotifier extends Notifier<CheckinState> {
  @override
  CheckinState build() {
    // Check status on build
    _checkStatus();
    return const CheckinState();
  }

  /// Check if user has already checked in today.
  Future<void> _checkStatus() async {
    final auth = ref.read(authProvider);
    if (auth.token == null) return;

    try {
      final repo = CheckinRepository();
      final result = await repo.getCheckinStatus(auth.token!);
      if (result != null) {
        state = state.copyWith(
          checkedIn: result.alreadyChecked,
          lastResult: result,
        );
      }
    } catch (e) {
      debugPrint('[Checkin] status check failed: $e');
    }
  }

  /// Perform check-in.
  Future<void> checkin() async {
    if (state.loading || state.checkedIn) return;

    final auth = ref.read(authProvider);
    if (auth.token == null) {
      AppNotifier.error(S.current.checkinNeedLogin);
      return;
    }

    state = state.copyWith(loading: true, error: null);

    try {
      final repo = CheckinRepository();
      final result = await repo.checkin(auth.token!);

      if (result.alreadyChecked && state.lastResult == null) {
        // Server says already checked but we didn't know — update state
        state = state.copyWith(
          checkedIn: true,
          loading: false,
          lastResult: result,
        );
        AppNotifier.warning(S.current.checkinAlready);
        return;
      }

      state = state.copyWith(
        checkedIn: true,
        loading: false,
        lastResult: result,
      );

      // Show reward toast
      final rewardText = result.type == 'traffic'
          ? S.current.checkinTrafficReward(result.amountText)
          : S.current.checkinBalanceReward(result.amountText);
      AppNotifier.success(rewardText);

      // Refresh user profile to reflect new traffic/balance
      ref.read(authProvider.notifier).refreshUserInfo();
    } on XBoardApiException catch (e) {
      state = state.copyWith(loading: false, error: e.message);
      AppNotifier.error(e.message);
    } catch (e) {
      debugPrint('[Checkin] error: $e');
      state = state.copyWith(loading: false, error: e.toString());
      AppNotifier.error(S.current.checkinFailed);
    }
  }

  /// Refresh check-in status (e.g. after midnight).
  Future<void> refresh() async {
    state = const CheckinState();
    await _checkStatus();
  }
}
