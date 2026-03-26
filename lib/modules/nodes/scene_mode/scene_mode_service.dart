import '../../../core/storage/settings_service.dart';
import 'scene_mode.dart';

/// Persistence layer for [SceneMode].
///
/// Reads/writes to [SettingsService] under the key `'sceneMode'`.
/// Thin wrapper — all business logic lives in [SceneModeNotifier].
class SceneModeService {
  SceneModeService._();

  static Future<SceneMode> load() async {
    final key = await SettingsService.getSceneMode();
    return SceneMode.fromKey(key);
  }

  static Future<void> save(SceneMode mode) async {
    await SettingsService.setSceneMode(mode.settingsKey);
  }
}
