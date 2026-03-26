/// Data models for the Smart Select feature.
library;

/// A proxy node candidate collected for delay testing.
class SmartSelectCandidate {
  final String name;

  /// The group to call changeProxy on first.
  /// For direct nodes: this is the main selector group.
  /// For sub-group nodes: this is the sub-group containing the node.
  final String primaryGroup;

  /// What to select in [primaryGroup] (always equal to [name]).
  final String primarySelection;

  /// If node is inside a sub-group, also switch the main selector group
  /// to point at the sub-group. Null for direct nodes.
  final String? secondaryGroup;

  /// What to select in [secondaryGroup] (the sub-group name). Null for direct nodes.
  final String? secondarySelection;

  const SmartSelectCandidate({
    required this.name,
    required this.primaryGroup,
    required this.primarySelection,
    this.secondaryGroup,
    this.secondarySelection,
  });
}

/// A single scored and ranked proxy node.
class ScoredNode {
  final String name;
  final String type;

  /// Latency in ms. -1 means failed / timeout.
  final int delay;

  /// Score 0–100. Higher is better. 0 means failed/timeout.
  final int score;

  /// Region label inferred from the node name (e.g. "🇭🇰 香港").
  final String? region;

  /// Apply path — see [SmartSelectCandidate] for semantics.
  final String primaryGroup;
  final String primarySelection;
  final String? secondaryGroup;
  final String? secondarySelection;

  const ScoredNode({
    required this.name,
    required this.type,
    required this.delay,
    required this.score,
    this.region,
    required this.primaryGroup,
    required this.primarySelection,
    this.secondaryGroup,
    this.secondarySelection,
  });

  bool get isAvailable => delay > 0;

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'delay': delay,
        'score': score,
        if (region != null) 'region': region,
        'primaryGroup': primaryGroup,
        'primarySelection': primarySelection,
        if (secondaryGroup != null) 'secondaryGroup': secondaryGroup,
        if (secondarySelection != null) 'secondarySelection': secondarySelection,
      };

  factory ScoredNode.fromJson(Map<String, dynamic> json) => ScoredNode(
        name: json['name'] as String,
        type: json['type'] as String? ?? '',
        delay: json['delay'] as int? ?? -1,
        score: json['score'] as int? ?? 0,
        region: json['region'] as String?,
        primaryGroup: json['primaryGroup'] as String,
        primarySelection: json['primarySelection'] as String,
        secondaryGroup: json['secondaryGroup'] as String?,
        secondarySelection: json['secondarySelection'] as String?,
      );
}

/// The output of a completed smart-select run.
class SmartSelectResult {
  /// Top-N recommended nodes, sorted by score descending.
  final List<ScoredNode> top;

  /// Total number of nodes that were tested.
  final int totalTested;

  /// Number of nodes that responded (delay > 0).
  final int totalAvailable;

  const SmartSelectResult({
    required this.top,
    required this.totalTested,
    required this.totalAvailable,
  });
}

// ---------------------------------------------------------------------------
// Cache
// ---------------------------------------------------------------------------

/// A snapshot of the last smart-select run, persisted to disk.
///
/// Keyed by scene mode so results from different scenes never mix.
/// Freshness window: 5 minutes ([isFresh]).
class SmartSelectCache {
  final List<ScoredNode> top;
  final int totalTested;
  final int totalAvailable;

  /// UTC timestamp of when this result was recorded.
  final DateTime timestamp;

  /// [SceneMode.name] value at the time of the test (e.g. 'daily', 'ai').
  final String sceneMode;

  const SmartSelectCache({
    required this.top,
    required this.totalTested,
    required this.totalAvailable,
    required this.timestamp,
    required this.sceneMode,
  });

  /// True when the cache is less than 5 minutes old.
  bool get isFresh =>
      DateTime.now().difference(timestamp).inMinutes < 5;

  /// Human-readable age label shown in the UI.
  String get ageLabel {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inSeconds < 60) return '刚刚';
    if (diff.inMinutes < 60) return '${diff.inMinutes} 分钟前';
    if (diff.inHours < 24) return '${diff.inHours} 小时前';
    return '${diff.inDays} 天前';
  }

  /// Convert to a [SmartSelectResult] for the UI to consume.
  SmartSelectResult toResult() => SmartSelectResult(
        top: top,
        totalTested: totalTested,
        totalAvailable: totalAvailable,
      );

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toUtc().toIso8601String(),
        'sceneMode': sceneMode,
        'totalTested': totalTested,
        'totalAvailable': totalAvailable,
        'top': top.map((n) => n.toJson()).toList(),
      };

  factory SmartSelectCache.fromJson(Map<String, dynamic> json) =>
      SmartSelectCache(
        timestamp: DateTime.parse(json['timestamp'] as String).toLocal(),
        sceneMode: json['sceneMode'] as String? ?? 'daily',
        totalTested: json['totalTested'] as int? ?? 0,
        totalAvailable: json['totalAvailable'] as int? ?? 0,
        top: (json['top'] as List<dynamic>? ?? [])
            .whereType<Map<String, dynamic>>()
            .map(ScoredNode.fromJson)
            .toList(),
      );
}
