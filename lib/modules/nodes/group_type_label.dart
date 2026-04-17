import 'package:flutter/widgets.dart';

import '../../domain/models/proxy.dart';

/// Returns a localized label for proxy group types.
///
/// Uses the current locale from [context] to decide between Chinese and English.
String groupTypeLabel(BuildContext context, String type) {
  final isEn = Localizations.localeOf(context).languageCode == 'en';
  switch (type) {
    case 'Selector':
      return isEn ? 'Select' : '手动选择';
    case 'URLTest':
      return isEn ? 'Auto' : '自动选择';
    case 'Fallback':
      return isEn ? 'Fallback' : '故障转移';
    case 'LoadBalance':
      return isEn ? 'Balance' : '负载均衡';
    default:
      return type;
  }
}

/// Label shown in a proxy-group header's selection badge.
///
/// Always prefers the currently-selected node name — that's what users
/// actually care about ("what am I using right now"), and it matches the
/// convention of Clash Verge Rev, FlClash, and metacubexd. For URLTest /
/// Fallback / LoadBalance groups, [ProxyGroup.now] is the auto-picked node;
/// for Selector groups it's the user's last choice. Fall back to the type
/// label only when mihomo hasn't populated `now` yet (fresh start before
/// the first URL test completes).
String groupSelectionLabel(BuildContext context, ProxyGroup group) {
  if (group.now.isNotEmpty) return group.now;
  return groupTypeLabel(context, group.type);
}
