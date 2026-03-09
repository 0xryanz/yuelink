import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ffi/core_controller.dart';
import '../models/proxy.dart';

// ------------------------------------------------------------------
// Proxy groups & nodes
// ------------------------------------------------------------------

final proxyGroupsProvider =
    StateNotifierProvider<ProxyGroupsNotifier, List<ProxyGroup>>(
  (ref) => ProxyGroupsNotifier(),
);

class ProxyGroupsNotifier extends StateNotifier<List<ProxyGroup>> {
  ProxyGroupsNotifier() : super([]);

  void refresh() {
    final data = CoreController.instance.getProxies();
    final proxiesMap = data['proxies'] as Map<String, dynamic>? ?? {};

    final groups = <ProxyGroup>[];
    for (final entry in proxiesMap.entries) {
      final info = entry.value as Map<String, dynamic>;
      if (info.containsKey('all')) {
        groups.add(ProxyGroup(
          name: entry.key,
          type: info['type'] as String? ?? '',
          all: (info['all'] as List?)?.cast<String>() ?? [],
          now: info['now'] as String? ?? '',
        ));
      }
    }
    state = groups;
  }

  bool changeProxy(String groupName, String proxyName) {
    final ok = CoreController.instance.changeProxy(groupName, proxyName);
    if (ok) refresh();
    return ok;
  }
}

// ------------------------------------------------------------------
// Delay testing
// ------------------------------------------------------------------

final delayResultsProvider = StateProvider<Map<String, int>>((ref) => {});
final delayTestingProvider = StateProvider<Set<String>>((ref) => {});

final delayTestProvider =
    Provider<DelayTestActions>((ref) => DelayTestActions(ref));

class DelayTestActions {
  final Ref ref;
  DelayTestActions(this.ref);

  /// Test delay for a single proxy node (async to not block UI).
  Future<int> testDelay(String proxyName) async {
    // Mark as testing
    final testing = Set<String>.from(ref.read(delayTestingProvider));
    testing.add(proxyName);
    ref.read(delayTestingProvider.notifier).state = testing;

    // Run in isolate-friendly way (compute for mock, direct for real)
    final delay = await Future(() {
      return CoreController.instance.testDelay(proxyName);
    });

    // Update results
    final current = Map<String, int>.from(ref.read(delayResultsProvider));
    current[proxyName] = delay;
    ref.read(delayResultsProvider.notifier).state = current;

    // Unmark testing
    final doneSet = Set<String>.from(ref.read(delayTestingProvider));
    doneSet.remove(proxyName);
    ref.read(delayTestingProvider.notifier).state = doneSet;

    return delay;
  }

  /// Test all proxies in a group sequentially.
  Future<void> testGroup(List<String> proxyNames) async {
    for (final name in proxyNames) {
      await testDelay(name);
      // Small gap to let UI update
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }
}
