import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

class ExitIpState {
  final String? ip;
  final String? country;
  final bool isLoading;
  final bool isQueried;

  const ExitIpState({
    this.ip,
    this.country,
    this.isLoading = false,
    this.isQueried = false,
  });

  ExitIpState copyWith({
    String? ip,
    String? country,
    bool? isLoading,
    bool? isQueried,
  }) =>
      ExitIpState(
        ip: ip ?? this.ip,
        country: country ?? this.country,
        isLoading: isLoading ?? this.isLoading,
        isQueried: isQueried ?? this.isQueried,
      );
}

class ExitIpNotifier extends StateNotifier<ExitIpState> {
  ExitIpNotifier() : super(const ExitIpState());

  Future<void> query() async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true);
    try {
      final httpClient = HttpClient();
      try {
        final request = await httpClient
            .getUrl(Uri.parse('http://ip-api.com/json/?fields=query,country'))
            .timeout(const Duration(seconds: 8));
        final response =
            await request.close().timeout(const Duration(seconds: 8));
        if (response.statusCode == 200) {
          final body = await response.transform(utf8.decoder).join();
          final qm = RegExp(r'"query"\s*:\s*"([^"]+)"').firstMatch(body);
          final cm = RegExp(r'"country"\s*:\s*"([^"]+)"').firstMatch(body);
          if (mounted) {
            state = ExitIpState(
              ip: qm?.group(1),
              country: cm?.group(1),
              isLoading: false,
              isQueried: true,
            );
          }
          return;
        }
      } finally {
        httpClient.close();
      }
    } catch (_) {}
    if (mounted) {
      state = ExitIpState(isLoading: false, isQueried: true);
    }
  }

  void reset() => state = const ExitIpState();
}

final exitIpProvider =
    StateNotifierProvider.autoDispose<ExitIpNotifier, ExitIpState>(
  (ref) => ExitIpNotifier(),
);
