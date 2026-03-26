import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// A single entry in the "recently used" list.
class RecentNode {
  final String name;
  final String group;
  const RecentNode({required this.name, required this.group});

  Map<String, dynamic> toJson() => {'name': name, 'group': group};

  static RecentNode fromJson(Map<String, dynamic> m) =>
      RecentNode(name: m['name'] as String, group: m['group'] as String);
}

/// Persists node favorites and recent-usage list to
/// `<AppSupport>/node_favorites.json`.
///
/// Format:
/// ```json
/// {
///   "favorites": ["NodeA", "NodeB"],
///   "recent": [{"name": "NodeA", "group": "PROXIES"}, ...]
/// }
/// ```
class NodeFavoritesService {
  static const _fileName = 'node_favorites.json';
  static const _maxRecent = 5;

  static Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }

  static Future<Map<String, dynamic>> _readRaw() async {
    try {
      final f = await _file();
      if (!f.existsSync()) return {};
      final content = await f.readAsString();
      return jsonDecode(content) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  static Future<void> _writeRaw(Map<String, dynamic> data) async {
    final f = await _file();
    await f.parent.create(recursive: true);
    // Atomic write via tmp + rename
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(data));
    await tmp.rename(f.path);
  }

  // ── Favorites ─────────────────────────────────────────────────────────────

  static Future<Set<String>> getFavorites() async {
    final data = await _readRaw();
    final list = data['favorites'] as List? ?? [];
    return list.map((e) => e.toString()).toSet();
  }

  static Future<void> saveFavorites(Set<String> favorites) async {
    final data = await _readRaw();
    data['favorites'] = favorites.toList();
    await _writeRaw(data);
  }

  // ── Recent ────────────────────────────────────────────────────────────────

  static Future<List<RecentNode>> getRecent() async {
    final data = await _readRaw();
    final list = data['recent'] as List? ?? [];
    return list
        .whereType<Map<String, dynamic>>()
        .map(RecentNode.fromJson)
        .toList();
  }

  static Future<void> saveRecent(List<RecentNode> recent) async {
    final data = await _readRaw();
    data['recent'] = recent.take(_maxRecent).map((n) => n.toJson()).toList();
    await _writeRaw(data);
  }
}
