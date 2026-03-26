import '../../../domain/models/proxy.dart';
import '../scene_mode/scene_mode.dart';
import 'smart_select_result.dart';

/// Pure scoring and candidate-collection logic. No Riverpod dependencies.
class SmartSelectService {
  SmartSelectService._();

  /// Maximum number of nodes to test in one smart-select run.
  static const int maxCandidates = 40;

  /// Map a latency (ms) to a score 0–100.
  /// 0 means failed/timeout. Higher = faster.
  static int scoreDelay(int delay) {
    if (delay <= 0) return 0;
    if (delay <= 80) return 100;
    if (delay <= 150) return 90;
    if (delay <= 250) return 75;
    if (delay <= 400) return 55;
    if (delay <= 600) return 35;
    return 15;
  }

  /// Infer a region emoji + label from a node name.
  /// Returns null if the region cannot be determined.
  static String? inferRegion(String name) {
    final l = name.toLowerCase();
    if (name.contains('🇭🇰') || l.contains('香港') || _word(l, 'hk')) return '🇭🇰 香港';
    if (name.contains('🇹🇼') || l.contains('台湾') || l.contains('台北') || _word(l, 'tw')) return '🇹🇼 台湾';
    if (name.contains('🇸🇬') || l.contains('新加坡') || _word(l, 'sg')) return '🇸🇬 新加坡';
    if (name.contains('🇯🇵') || l.contains('日本') || _word(l, 'jp')) return '🇯🇵 日本';
    if (name.contains('🇺🇸') || l.contains('美国') || _word(l, 'us')) return '🇺🇸 美国';
    if (name.contains('🇰🇷') || l.contains('韩国') || _word(l, 'kr')) return '🇰🇷 韩国';
    if (name.contains('🇬🇧') || l.contains('英国') || _word(l, 'uk')) return '🇬🇧 英国';
    if (name.contains('🇩🇪') || l.contains('德国') || _word(l, 'de')) return '🇩🇪 德国';
    if (name.contains('🇫🇷') || l.contains('法国') || _word(l, 'fr')) return '🇫🇷 法国';
    if (name.contains('🇨🇦') || l.contains('加拿大') || _word(l, 'ca')) return '🇨🇦 加拿大';
    if (name.contains('🇦🇺') || l.contains('澳大利亚') || l.contains('澳洲') || _word(l, 'au')) return '🇦🇺 澳洲';
    if (name.contains('🇮🇳') || l.contains('印度') || _word(l, 'in')) return '🇮🇳 印度';
    if (name.contains('🇷🇺') || l.contains('俄罗斯') || _word(l, 'ru')) return '🇷🇺 俄罗斯';
    if (name.contains('🇧🇷') || l.contains('巴西') || _word(l, 'br')) return '🇧🇷 巴西';
    if (name.contains('🇦🇷') || l.contains('阿根廷') || _word(l, 'ar')) return '🇦🇷 阿根廷';
    if (name.contains('🇳🇱') || l.contains('荷兰') || _word(l, 'nl')) return '🇳🇱 荷兰';
    return null;
  }

  /// True if [word] appears as a standalone token in [lower] (surrounded by
  /// non-alphanumeric chars or at string boundaries).
  static bool _word(String lower, String word) {
    final idx = lower.indexOf(word);
    if (idx == -1) return false;
    final before = idx == 0 || !RegExp(r'[a-z0-9]').hasMatch(lower[idx - 1]);
    final after = idx + word.length >= lower.length ||
        !RegExp(r'[a-z0-9]').hasMatch(lower[idx + word.length]);
    return before && after;
  }

  /// Collect up to [maxCandidates] testable nodes starting from [mainGroupName].
  ///
  /// Expands one level of sub-groups (region groups) so that individual proxy
  /// nodes inside them are also tested.
  static List<SmartSelectCandidate> collectCandidates({
    required List<ProxyGroup> groups,
    required Map<String, String> nodeTypes,
    required String mainGroupName,
  }) {
    ProxyGroup? mainGroup;
    for (final g in groups) {
      if (g.name == mainGroupName) {
        mainGroup = g;
        break;
      }
    }
    if (mainGroup == null) return [];

    final groupIndex = <String, ProxyGroup>{
      for (final g in groups) g.name: g,
    };

    final candidates = <SmartSelectCandidate>[];
    final seen = <String>{};

    for (final item in mainGroup.all) {
      if (candidates.length >= maxCandidates) break;
      if (seen.contains(item)) continue;

      if (nodeTypes.containsKey(item)) {
        // Direct individual node in the main group
        seen.add(item);
        candidates.add(SmartSelectCandidate(
          name: item,
          primaryGroup: mainGroupName,
          primarySelection: item,
        ));
      } else {
        // May be a sub-group (e.g., region group) — expand one level
        final sub = groupIndex[item];
        if (sub == null) continue;
        for (final node in sub.all) {
          if (candidates.length >= maxCandidates) break;
          if (seen.contains(node) || !nodeTypes.containsKey(node)) continue;
          seen.add(node);
          candidates.add(SmartSelectCandidate(
            name: node,
            primaryGroup: sub.name,
            primarySelection: node,
            secondaryGroup: mainGroupName,
            secondarySelection: sub.name,
          ));
        }
      }
    }

    return candidates;
  }

  /// Build the final ranked result from tested delays.
  ///
  /// When [sceneConfig] is provided, bonus points are added on top of the
  /// base latency score so that scene-preferred nodes surface to the top:
  ///
  ///   daily     → +0   (neutral, pure latency ranking)
  ///   ai        → up to +30  (node keyword +20, group +10)
  ///   streaming → up to +30  (node keyword +20, group +10)
  ///   gaming    → up to +45  (node keyword +15, group +5, latency +25)
  static SmartSelectResult buildResult({
    required List<SmartSelectCandidate> candidates,
    required Map<String, int> delays,
    required Map<String, String> nodeTypes,
    SceneModeConfig? sceneConfig,
    int topN = 3,
  }) {
    final scored = candidates.map((c) {
      final delay = delays[c.name] ?? -1;
      final base = scoreDelay(delay);
      final adjusted = (delay > 0 && sceneConfig != null)
          ? _applySceneBonus(base, c, delay, sceneConfig)
          : base;
      return ScoredNode(
        name: c.name,
        type: nodeTypes[c.name] ?? '',
        delay: delay,
        score: adjusted,
        region: inferRegion(c.name),
        primaryGroup: c.primaryGroup,
        primarySelection: c.primarySelection,
        secondaryGroup: c.secondaryGroup,
        secondarySelection: c.secondarySelection,
      );
    }).toList();

    // Sort: adjusted score descending; ties broken by raw delay ascending
    scored.sort((a, b) {
      if (a.score != b.score) return b.score.compareTo(a.score);
      final da = a.delay > 0 ? a.delay : 99999;
      final db = b.delay > 0 ? b.delay : 99999;
      return da.compareTo(db);
    });

    final available = scored.where((n) => n.isAvailable).toList();
    return SmartSelectResult(
      top: available.take(topN).toList(),
      totalTested: candidates.length,
      totalAvailable: available.length,
    );
  }

  /// Apply scene-mode bonus points on top of the base latency score.
  ///
  /// Rules:
  ///   - Node name matches a [SceneModeConfig.preferredNodeKeywords] entry:
  ///       AI / streaming → +20, gaming → +15  (first match only)
  ///   - Primary group name matches a [SceneModeConfig.preferredGroupPatterns] entry:
  ///       AI / streaming → +10, gaming → +5   (first match only)
  ///   - [SceneModeConfig.preferLowLatency] is true (gaming only):
  ///       delay ≤  80 ms → +25
  ///       delay ≤ 150 ms → +15
  ///       delay ≤ 250 ms → +5
  ///
  /// Scores may exceed 100; they are used for comparison only.
  static int _applySceneBonus(
    int base,
    SmartSelectCandidate candidate,
    int delay,
    SceneModeConfig config,
  ) {
    // Daily mode: no keywords, no latency preference → skip
    if (config.preferredNodeKeywords.isEmpty && !config.preferLowLatency) {
      return base;
    }

    int bonus = 0;
    final nameLower = candidate.name.toLowerCase();
    final groupLower = candidate.primaryGroup.toLowerCase();

    // Gaming uses smaller keyword bonus (latency bonus compensates)
    final kwBonus = config.preferLowLatency ? 15 : 20;
    final groupBonus = config.preferLowLatency ? 5 : 10;

    // Node keyword match — first match only
    for (final kw in config.preferredNodeKeywords) {
      if (nameLower.contains(kw.toLowerCase())) {
        bonus += kwBonus;
        break;
      }
    }

    // Group pattern match — first match only
    for (final pat in config.preferredGroupPatterns) {
      if (groupLower.contains(pat.toLowerCase())) {
        bonus += groupBonus;
        break;
      }
    }

    // Low-latency bonus (gaming mode only)
    if (config.preferLowLatency) {
      if (delay <= 80) {
        bonus += 25;
      } else if (delay <= 150) {
        bonus += 15;
      } else if (delay <= 250) {
        bonus += 5;
      }
    }

    return base + bonus;
  }
}
