import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ffi/core_mock.dart';
import '../domain/models/rule.dart';
import '../core/kernel/core_manager.dart';

final rulesProvider =
    StateNotifierProvider<RulesNotifier, List<RuleInfo>>(
  (ref) => RulesNotifier(),
);

class RulesNotifier extends StateNotifier<List<RuleInfo>> {
  RulesNotifier() : super([]);

  Future<void> refresh() async {
    final manager = CoreManager.instance;

    Map<String, dynamic> data;
    if (manager.isMockMode) {
      data = CoreMock.instance.getRules();
    } else {
      try {
        data = await manager.api.getRules();
      } catch (_) {
        return;
      }
    }

    final rules = (data['rules'] as List?)
            ?.map((e) => RuleInfo.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
    state = rules;
  }
}
