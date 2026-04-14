import 'package:flutter/material.dart';

/// iOS-style colored squircle icon for settings rows.
/// Matches iOS 18+ Settings app: small rounded square with white icon
/// on a colored background. Size default 29x29 (iOS standard).
class YLSettingIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final double iconSize;

  const YLSettingIcon({
    super.key,
    required this.icon,
    required this.color,
    this.size = 29,
    this.iconSize = 18,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size * 0.23), // iOS squircle ratio
      ),
      child: Icon(
        icon,
        color: Colors.white,
        size: iconSize,
      ),
    );
  }
}
