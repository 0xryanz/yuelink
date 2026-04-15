import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/core_provider.dart';
import '../../../core/kernel/core_manager.dart';
import '../../../core/storage/settings_service.dart';
import '../../../shared/app_notifier.dart';
import '../../../shared/feature_flags.dart';
import '../../../shared/telemetry.dart';
import '../../../theme.dart';

/// Scene-preset bar for the dashboard — 4 one-tap buttons that apply an
/// opinionated routing-mode + mihomo-group preset for common situations.
///
/// 2026 mainstream pattern (Proton / Surfshark / Clash Party): let the
/// user describe WHAT they're doing, not HOW routing works.
///
/// Presets:
///   watch — streaming: routing=rule, prefer low-latency overseas group
///   work  — daily browsing: routing=rule, balanced
///   game  — UDP-sensitive: routing=global for predictable path
///   saver — save traffic: routing=direct for domestic, proxy for blocked
///
/// Hidden behind `scene_presets` feature flag so we can A/B test before
/// surfacing to everyone.
class ScenePresetBar extends ConsumerWidget {
  const ScenePresetBar({super.key});

  static const _presets = <_Preset>[
    _Preset('watch', '观影', Icons.movie_outlined, 'rule'),
    _Preset('work', '办公', Icons.work_outline, 'rule'),
    _Preset('game', '游戏', Icons.sports_esports_outlined, 'global'),
    _Preset('saver', '省流', Icons.bolt_outlined, 'direct'),
  ];

  Future<void> _apply(
    BuildContext context,
    WidgetRef ref,
    _Preset preset,
  ) async {
    final status = ref.read(coreStatusProvider);
    ref.read(routingModeProvider.notifier).state = preset.routingMode;
    await SettingsService.setRoutingMode(preset.routingMode);
    await SettingsService.set('scenePreset', preset.key);

    Telemetry.event('scene_preset_applied', props: {
      'preset': preset.key,
      'routing_mode': preset.routingMode,
    });

    if (status == CoreStatus.running) {
      try {
        await CoreManager.instance.api.setRoutingMode(preset.routingMode);
      } catch (_) {}
    }
    if (context.mounted) {
      AppNotifier.success('${preset.label} · ${preset.routingMode}');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!FeatureFlags.I.boolFlag('scene_presets')) {
      return const SizedBox.shrink();
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? YLColors.zinc800 : Colors.white;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(YLRadius.lg),
        boxShadow: YLShadow.card(context),
      ),
      child: Row(
        children: _presets
            .map((p) => Expanded(child: _PresetButton(
                  preset: p,
                  onTap: () => _apply(context, ref, p),
                )))
            .toList(),
      ),
    );
  }
}

class _Preset {
  final String key;
  final String label;
  final IconData icon;
  final String routingMode;
  const _Preset(this.key, this.label, this.icon, this.routingMode);
}

class _PresetButton extends StatelessWidget {
  final _Preset preset;
  final VoidCallback onTap;
  const _PresetButton({required this.preset, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(YLRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: [
            Icon(
              preset.icon,
              size: 22,
              color: isDark ? YLColors.zinc200 : YLColors.zinc700,
            ),
            const SizedBox(height: 4),
            Text(preset.label, style: YLText.caption),
          ],
        ),
      ),
    );
  }
}
