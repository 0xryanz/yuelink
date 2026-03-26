import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../home_content_provider.dart';
import 'hero_banner_model.dart';

// ── Banner provider ───────────────────────────────────────────────────────────

/// Provides the current list of [HeroBannerItem]s for the homepage carousel.
///
/// Delegates to [heroBannerConfigProvider] from the unified config layer
/// ([home_content_provider.dart]). The static editorial content has moved to
/// [kLocalHeroBanners] in [hero_banner_model.dart].
///
/// The [HeroBanner] widget reads this provider unchanged — no widget edits needed
/// when migrating the config layer from v1 static to v2 server-driven.
final heroBannerItemsProvider = Provider<List<HeroBannerItem>>((ref) {
  return ref.watch(heroBannerConfigProvider);
});
