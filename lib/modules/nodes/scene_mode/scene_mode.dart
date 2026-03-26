/// Scene mode definitions.
///
/// v1: Hardcoded presets. Future v2 can extend [SceneModeConfig] with
/// server-provided overrides by merging a remote JSON on top of [defaults].
library;

// ── Enum ─────────────────────────────────────────────────────────────────────

enum SceneMode {
  daily,
  ai,
  streaming,
  gaming;

  String get label {
    switch (this) {
      case SceneMode.daily:
        return '日常';
      case SceneMode.ai:
        return 'AI';
      case SceneMode.streaming:
        return '流媒体';
      case SceneMode.gaming:
        return '游戏';
    }
  }

  String get icon {
    switch (this) {
      case SceneMode.daily:
        return '☀️';
      case SceneMode.ai:
        return '🤖';
      case SceneMode.streaming:
        return '🎬';
      case SceneMode.gaming:
        return '🎮';
    }
  }

  String get settingsKey => name; // 'daily' | 'ai' | 'streaming' | 'gaming'

  static SceneMode fromKey(String key) {
    return SceneMode.values.firstWhere(
      (m) => m.name == key,
      orElse: () => SceneMode.daily,
    );
  }
}

// ── Config model ─────────────────────────────────────────────────────────────

/// Preferences bundled with each scene mode (v1: local only).
///
/// Extension points for v2:
/// - [remoteConfigKey]: backend can push overrides under this key.
/// - [preferredGroupPatterns] / [preferredNodeKeywords]: used by future
///   smart-select logic to auto-pick nodes matching the scene.
class SceneModeConfig {
  final SceneMode mode;
  final String description;

  /// mihomo routing mode: 'rule' | 'global' | 'direct'
  final String routingMode;

  /// Keywords to prefer when auto-selecting a proxy group (case-insensitive).
  /// e.g. ['Netflix', 'NF', '流媒体'] for streaming.
  /// v1: stored as preference, not yet acted upon automatically.
  final List<String> preferredGroupPatterns;

  /// Keywords to prefer when auto-selecting a node within a group.
  final List<String> preferredNodeKeywords;

  /// If true, prefer nodes with lower measured latency over keyword match.
  final bool preferLowLatency;

  const SceneModeConfig({
    required this.mode,
    required this.description,
    required this.routingMode,
    this.preferredGroupPatterns = const [],
    this.preferredNodeKeywords = const [],
    this.preferLowLatency = false,
  });

  // ── v2 extension point ──────────────────────────────────────────────────
  // Future: merge remote JSON override via:
  //   SceneModeConfig.fromRemote(base: defaults[mode]!, remoteJson: json)
}

// ── Hardcoded presets ─────────────────────────────────────────────────────────

/// Default configs for all 4 scene modes.
const Map<SceneMode, SceneModeConfig> kSceneModeDefaults = {
  SceneMode.daily: SceneModeConfig(
    mode: SceneMode.daily,
    description: '平衡策略，适合日常浏览和社交',
    routingMode: 'rule',
    preferredGroupPatterns: [],
    preferredNodeKeywords: [],
    preferLowLatency: false,
  ),
  SceneMode.ai: SceneModeConfig(
    mode: SceneMode.ai,
    description: '优先 ChatGPT / Claude 可用节点',
    routingMode: 'rule',
    preferredGroupPatterns: ['AI', 'GPT', 'OpenAI', '美国', 'US'],
    preferredNodeKeywords: ['美国', 'US', 'GPT', 'AI', '硅谷'],
    preferLowLatency: false,
  ),
  SceneMode.streaming: SceneModeConfig(
    mode: SceneMode.streaming,
    description: '优先流媒体解锁节点（Netflix / Disney+）',
    routingMode: 'rule',
    preferredGroupPatterns: ['Netflix', 'NF', '流媒体', '解锁', 'HK', '香港'],
    preferredNodeKeywords: ['Netflix', 'NF', '流媒体', '解锁', '香港', 'HK', '狮城', 'SG'],
    preferLowLatency: false,
  ),
  SceneMode.gaming: SceneModeConfig(
    mode: SceneMode.gaming,
    description: '优先低延迟节点，适合游戏加速',
    routingMode: 'rule',
    preferredGroupPatterns: ['游戏', 'Game', '日本', 'JP', '韩国', 'KR'],
    preferredNodeKeywords: ['日本', 'JP', '韩国', 'KR', '游戏', 'Game'],
    preferLowLatency: true,
  ),
};
