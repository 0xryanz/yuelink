import 'package:flutter/material.dart';

import '../../theme.dart';

/// Premium empty state widget with layered icon, message, and optional action.
///
/// Visual: a large soft-gradient circle background with a clean icon on top,
/// message below, optional action button. Replaces plain Icon+Text throughout
/// the app for a more polished look.
class YLEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? action;
  final double size;

  const YLEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.action,
    this.size = 96,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = YLColors.currentAccent;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Layered circle background with soft gradient using accent color
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                accent.withValues(alpha: isDark ? 0.15 : 0.08),
                accent.withValues(alpha: 0.0),
              ],
            ),
          ),
          child: Icon(
            icon,
            size: size * 0.45,
            color: accent.withValues(alpha: isDark ? 0.7 : 0.5),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          title,
          style: YLText.body.copyWith(
            color: isDark ? YLColors.zinc300 : YLColors.zinc600,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            style: YLText.caption.copyWith(color: YLColors.zinc400),
            textAlign: TextAlign.center,
          ),
        ],
        if (action != null) ...[
          const SizedBox(height: 16),
          action!,
        ],
      ],
    );
  }
}
