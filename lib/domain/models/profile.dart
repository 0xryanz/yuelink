import '../../shared/formatters/subscription_parser.dart';

/// Where a profile came from. Used by logout to decide what to delete:
/// only profiles synced from a YueLink account get cleared on logout —
/// user-imported (manual) profiles are preserved across login/logout cycles
/// to prevent data loss reported by users.
enum ProfileSource {
  /// Synced from a YueLink account (XBoard subscription). Cleared on logout.
  account,
  /// Manually imported by the user (URL paste, file drop, scheme handler).
  /// Survives logout.
  manual,
}

/// Subscription profile.
class Profile {
  final String id;
  String name;
  String url;
  String? configContent;
  DateTime? lastUpdated;
  Duration updateInterval;
  SubscriptionInfo? subInfo;
  /// Provenance — see [ProfileSource]. Defaults to `manual` for backwards
  /// compatibility with profiles created before this field existed.
  ProfileSource source;

  Profile({
    required this.id,
    required this.name,
    required this.url,
    this.configContent,
    this.lastUpdated,
    this.updateInterval = const Duration(hours: 24),
    this.subInfo,
    this.source = ProfileSource.manual,
  });

  /// Whether the subscription data is available.
  bool get hasSubInfo => subInfo != null && subInfo!.total != null;

  /// Whether this profile was synced from a YueLink account (and should be
  /// deleted on logout).
  bool get isAccountManaged => source == ProfileSource.account;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'lastUpdated': lastUpdated?.toIso8601String(),
        'updateInterval': updateInterval.inSeconds,
        if (subInfo != null) 'subInfo': subInfo!.toJson(),
        'source': source.name,
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
      // Default unknown profiles (legacy data without 'source' key) to
      // `manual` so they're never silently deleted on logout.
      source: switch (json['source'] as String?) {
        'account' => ProfileSource.account,
        _ => ProfileSource.manual,
      },
    );
  }
}
