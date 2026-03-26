import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'scene_mode.dart';
import 'scene_mode_service.dart';

// ── Notifier ──────────────────────────────────────────────────────────────────

class SceneModeNotifier extends AsyncNotifier<SceneMode> {
  @override
  Future<SceneMode> build() => SceneModeService.load();

  /// Switch to [mode] and persist immediately.
  Future<void> setMode(SceneMode mode) async {
    state = const AsyncLoading();
    await SceneModeService.save(mode);
    state = AsyncData(mode);
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

/// The currently active [SceneMode]. Loads from disk on first access.
final sceneModeProvider =
    AsyncNotifierProvider<SceneModeNotifier, SceneMode>(SceneModeNotifier.new);

/// Convenience derived provider — current [SceneModeConfig] (never null).
/// Falls back to [SceneMode.daily] config while loading.
final sceneModeConfigProvider = Provider<SceneModeConfig>((ref) {
  final mode = ref.watch(sceneModeProvider).valueOrNull ?? SceneMode.daily;
  return kSceneModeDefaults[mode]!;
});
