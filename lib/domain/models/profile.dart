import '../../shared/formatters/subscription_parser.dart';

/// Subscription profile.
class Profile {
  final String id;
  String name;
  String url;
  String? configContent;
  DateTime? lastUpdated;
  Duration updateInterval;
  SubscriptionInfo? subInfo;

  Profile({
    required this.id,
    required this.name,
    required this.url,
    this.configContent,
    this.lastUpdated,
    this.updateInterval = const Duration(hours: 24),
    this.subInfo,
  });

  /// Whether the subscription data is available.
  bool get hasSubInfo => subInfo != null && subInfo!.total != null;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'lastUpdated': lastUpdated?.toIso8601String(),
        'updateInterval': updateInterval.inSeconds,
        if (subInfo != null) 'subInfo': subInfo!.toJson(),
      };

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      name: json['name'] as String,
      url: json['url'] as String,
      lastUpdated: json['lastUpdated'] != null
          ? DateTime.tryParse(json['lastUpdated'] as String)
          : null,
      updateInterval:
          Duration(seconds: json['updateInterval'] as int? ?? 86400),
      subInfo: json['subInfo'] != null
          ? SubscriptionInfo.fromJson(
              json['subInfo'] as Map<String, dynamic>)
          : null,
    );
  }
}
