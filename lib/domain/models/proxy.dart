/// Represents a single proxy node.
class ProxyNode {
  final String name;
  final String type; // ss, vmess, trojan, etc.
  int? delay; // latency in ms, null = untested
  bool alive;

  ProxyNode({
    required this.name,
    required this.type,
    this.delay,
    this.alive = true,
  });

  factory ProxyNode.fromJson(Map<String, dynamic> json) {
    return ProxyNode(
      name: json['name'] as String,
      type: json['type'] as String,
      delay: json['delay'] as int?,
      alive: json['alive'] as bool? ?? true,
    );
  }
}

/// Represents a proxy group (Selector, URLTest, Fallback, etc.)
class ProxyGroup {
  final String name;
  final String type; // Selector, URLTest, Fallback, LoadBalance
  final List<String> all; // all proxy names in this group
  String now; // currently selected proxy name

  ProxyGroup({
    required this.name,
    required this.type,
    required this.all,
    required this.now,
  });

  factory ProxyGroup.fromJson(Map<String, dynamic> json) {
    return ProxyGroup(
      name: json['name'] as String,
      type: json['type'] as String,
      all: (json['all'] as List?)?.cast<String>() ?? [],
      now: json['now'] as String? ?? '',
    );
  }
}
