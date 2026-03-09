import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../ffi/core_controller.dart';
import '../models/traffic.dart';
import '../services/vpn_service.dart';

// ------------------------------------------------------------------
// Core state
// ------------------------------------------------------------------

enum CoreStatus { stopped, starting, running, stopping }

final coreStatusProvider = StateProvider<CoreStatus>((ref) => CoreStatus.stopped);

final coreInitProvider = FutureProvider<bool>((ref) async {
  final appDir = await getApplicationSupportDirectory();
  return CoreController.instance.init(appDir.path);
});

/// Whether the core is running in mock mode (no native library).
final isMockModeProvider = Provider<bool>((ref) {
  return CoreController.instance.isMockMode;
});

// ------------------------------------------------------------------
// Core actions
// ------------------------------------------------------------------

final coreActionsProvider = Provider<CoreActions>((ref) => CoreActions(ref));

class CoreActions {
  final Ref ref;
  CoreActions(this.ref);

  Future<bool> start(String configYaml) async {
    ref.read(coreStatusProvider.notifier).state = CoreStatus.starting;

    // Small delay to show transition animation
    await Future.delayed(const Duration(milliseconds: 300));

    final core = CoreController.instance;
    final ok = core.start(configYaml);
    if (!ok) {
      ref.read(coreStatusProvider.notifier).state = CoreStatus.stopped;
      return false;
    }

    // Start platform VPN tunnel (skip in mock mode)
    if (!core.isMockMode) {
      await VpnService.startVpn();
    }

    ref.read(coreStatusProvider.notifier).state = CoreStatus.running;
    return true;
  }

  Future<void> stop() async {
    ref.read(coreStatusProvider.notifier).state = CoreStatus.stopping;
    await Future.delayed(const Duration(milliseconds: 300));

    final core = CoreController.instance;
    if (!core.isMockMode) {
      await VpnService.stopVpn();
    }
    core.stop();

    ref.read(coreStatusProvider.notifier).state = CoreStatus.stopped;
    ref.read(trafficProvider.notifier).state = const Traffic();
  }

  Future<void> toggle(String configYaml) async {
    final status = ref.read(coreStatusProvider);
    if (status == CoreStatus.running) {
      await stop();
    } else if (status == CoreStatus.stopped) {
      await start(configYaml);
    }
  }
}

// ------------------------------------------------------------------
// Traffic polling
// ------------------------------------------------------------------

final trafficProvider = StateProvider<Traffic>((ref) => const Traffic());

final trafficPollingProvider = Provider<Timer?>((ref) {
  final status = ref.watch(coreStatusProvider);
  if (status != CoreStatus.running) return null;

  final timer = Timer.periodic(const Duration(seconds: 1), (_) {
    final t = CoreController.instance.getTraffic();
    ref.read(trafficProvider.notifier).state = Traffic(up: t.up, down: t.down);
  });

  ref.onDispose(() => timer.cancel());
  return timer;
});
