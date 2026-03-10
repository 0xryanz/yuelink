import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

// ── Semantic colour tokens (Premium Apple/Vercel inspired) ───────────────────

class YLColors {
  YLColors._();

  // Backgrounds
  static const bgLight = Color(0xFFF4F4F5); // Very light gray for contrast
  static const bgDark  = Color(0xFF000000); // Pure black for OLED premium feel

  // Surfaces (Cards)
  static const surfaceLight = Color(0xFFFFFFFF);
  static const surfaceDark  = Color(0xFF1C1C1E); // Apple dark mode card color

  // Neutrals
  static const zinc400 = Color(0xFFA1A1AA);
  static const zinc500 = Color(0xFF71717A);
  static const zinc800 = Color(0xFF27272A);

  // Brand & Status
  static const primary    = Color(0xFF007AFF); // Apple Blue
  static const connected  = Color(0xFF34C759); // Apple Green
  static const connecting = Color(0xFFFF9F0A); // Apple Orange
  static const error      = Color(0xFFFF3B30); // Apple Red
}

// ── Typography scale ─────────────────────────────────────────────────────────

class YLText {
  YLText._();

  static const display = TextStyle(
      fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.8,
      fontFeatures: [FontFeature.tabularFigures()]);

  static const titleLarge = TextStyle(
      fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: -0.5);

  static const titleMedium = TextStyle(
      fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.3);

  static const body = TextStyle(
      fontSize: 15, fontWeight: FontWeight.w400, letterSpacing: -0.2);

  static const label = TextStyle(
      fontSize: 13, fontWeight: FontWeight.w500, letterSpacing: 0);

  static const caption = TextStyle(
      fontSize: 12, fontWeight: FontWeight.w400, letterSpacing: 0.1);

  static const mono = TextStyle(
      fontSize: 14, fontWeight: FontWeight.w500,
      fontFamily: 'Menlo',
      fontFeatures: [FontFeature.tabularFigures()]);
}

// ── Spacing & Radius ─────────────────────────────────────────────────────────

class YLSpacing {
  YLSpacing._();
  static const xs  = 4.0;
  static const sm  = 8.0;
  static const md  = 12.0;
  static const lg  = 16.0;
  static const xl  = 20.0;
  static const xxl = 24.0;
  static const massive = 32.0;
}

class YLRadius {
  YLRadius._();
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const pill = 999.0;
}

// ── Theme factory ────────────────────────────────────────────────────────────

ThemeData buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: isDark ? YLColors.bgDark : YLColors.bgLight,
    primaryColor: YLColors.primary,
    colorScheme: ColorScheme.fromSeed(
      seedColor: YLColors.primary,
      brightness: brightness,
      background: isDark ? YLColors.bgDark : YLColors.bgLight,
      surface: isDark ? YLColors.surfaceDark : YLColors.surfaceLight,
    ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03),
    fontFamily: '.SF Pro Text', // Native Apple font fallback
    dividerTheme: DividerThemeData(
      space: 1,
      thickness: 0.5,
      color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05),
    ),
  );
}

// ── Premium UI Components ────────────────────────────────────────────────────

/// A highly polished card surface.
class YLSurface extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final double borderRadius;

  const YLSurface({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.borderRadius = YLRadius.xl,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    Widget content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: isDark ? YLColors.surfaceDark : YLColors.surfaceLight,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.04),
          width: 0.5,
        ),
        boxShadow: isDark ? [] : [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(borderRadius),
          child: content,
        ),
      );
    }

    return content;
  }
}

/// Custom iOS-style grouped list item.
class YLGroupedListItem extends StatelessWidget {
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool isFirst;
  final bool isLast;

  const YLGroupedListItem({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.isFirst = false,
    this.isLast = false,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Material(
      color: isDark ? YLColors.surfaceDark : YLColors.surfaceLight,
      borderRadius: BorderRadius.vertical(
        top: isFirst ? const Radius.circular(YLRadius.lg) : Radius.zero,
        bottom: isLast ? const Radius.circular(YLRadius.lg) : Radius.zero,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.vertical(
          top: isFirst ? const Radius.circular(YLRadius.lg) : Radius.zero,
          bottom: isLast ? const Radius.circular(YLRadius.lg) : Radius.zero,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: YLSpacing.lg, vertical: YLSpacing.md),
          decoration: BoxDecoration(
            border: isLast ? null : Border(
              bottom: BorderSide(
                color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    DefaultTextStyle(
                      style: YLText.body.copyWith(color: isDark ? Colors.white : Colors.black),
                      child: title,
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      DefaultTextStyle(
                        style: YLText.caption.copyWith(color: YLColors.zinc500),
                        child: subtitle!,
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: YLSpacing.md),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Custom Pill-shaped Segmented Control (replaces ugly default SegmentedButton)
class YLPillSegmentedControl<T> extends StatelessWidget {
  final List<T> values;
  final List<String> labels;
  final T selectedValue;
  final ValueChanged<T> onChanged;

  const YLPillSegmentedControl({
    super.key,
    required this.values,
    required this.labels,
    required this.selectedValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.05),
        borderRadius: BorderRadius.circular(YLRadius.pill),
      ),
      child: Row(
        children: List.generate(values.length, (index) {
          final isSelected = values[index] == selectedValue;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(values[index]),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected 
                      ? (isDark ? YLColors.surfaceDark : YLColors.surfaceLight) 
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(YLRadius.pill),
                  boxShadow: isSelected && !isDark ? [
                    BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, 2))
                  ] : [],
                ),
                alignment: Alignment.center,
                child: Text(
                  labels[index],
                  style: YLText.label.copyWith(
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected 
                        ? (isDark ? Colors.white : Colors.black) 
                        : YLColors.zinc500,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class YLStatusDot extends StatelessWidget {
  final Color color;
  final double size;
  final bool glow;
  
  const YLStatusDot({super.key, required this.color, this.size = 8, this.glow = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle, 
        color: color,
        boxShadow: glow ? [
          BoxShadow(color: color.withOpacity(0.5), blurRadius: 8, spreadRadius: 2)
        ] : null,
      ),
    );
  }
}

class YLDelayBadge extends StatelessWidget {
  final int? delay;
  final bool testing;

  const YLDelayBadge({super.key, this.delay, this.testing = false});

  static Color colorFor(int d) {
    if (d <= 0) return YLColors.error;
    if (d < 150) return YLColors.connected;
    if (d < 300) return YLColors.connecting;
    return YLColors.error;
  }

  @override
  Widget build(BuildContext context) {
    if (testing) {
      return const SizedBox(
        width: 12, height: 12,
        child: CupertinoActivityIndicator(radius: 6),
      );
    }
    if (delay == null) {
      return Icon(Icons.speed_rounded, size: 14,
          color: Theme.of(context).colorScheme.onSurface.withOpacity(0.3));
    }
    final c = colorFor(delay!);
    return Text(
      delay! <= 0 ? 'Timeout' : '${delay}ms',
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: c,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}
