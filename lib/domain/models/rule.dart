/// A proxy rule from mihomo config.
class RuleInfo {
  final String type; // DOMAIN, DOMAIN-SUFFIX, GEOIP, MATCH, etc.
  final String payload; // the match pattern
  final String proxy; // target proxy group
  final int size; // provider rule count (for rule-set)

  const RuleInfo({
    required this.type,
    required this.payload,
    required this.proxy,
    this.size = 0,
  });

  factory RuleInfo.fromJson(Map<String, dynamic> json) {
    return RuleInfo(
      type: json['type'] as String? ?? '',
      payload: json['payload'] as String? ?? '',
      proxy: json['proxy'] as String? ?? '',
      size: json['size'] as int? ?? 0,
    );
  }
}
