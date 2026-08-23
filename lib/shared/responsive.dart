import 'package:flutter/widgets.dart';

/// Screen-width breakpoints and responsive helpers used across the app.
///
/// Breakpoints (device width, logical px):
///  - small : < 360
///  - normal: 360 - 430
///  - large : > 430
///
/// Always derive from the *available width* passed in by the caller
/// (MediaQuery width or a LayoutBuilder constraint), never from device type.
enum ScreenSize { small, normal, large }

abstract class Responsive {
  static const double smallMax = 360;
  static const double normalMax = 430;

  static ScreenSize sizeOf(BuildContext context) =>
      sizeForWidth(MediaQuery.sizeOf(context).width);

  static ScreenSize sizeForWidth(double width) {
    if (width < smallMax) return ScreenSize.small;
    if (width <= normalMax) return ScreenSize.normal;
    return ScreenSize.large;
  }

  static bool isSmall(BuildContext context) =>
      sizeOf(context) == ScreenSize.small;

  /// Scales a base value slightly down on small screens and slightly up on
  /// large screens. Use for paddings/gaps, not for critical min-tap-target sizes.
  static double scale(BuildContext context, double base) {
    switch (sizeOf(context)) {
      case ScreenSize.small:
        return base * 0.85;
      case ScreenSize.normal:
        return base;
      case ScreenSize.large:
        return base * 1.1;
    }
  }

  /// Horizontal page padding that shrinks on small screens.
  static double pagePadding(BuildContext context) {
    switch (sizeOf(context)) {
      case ScreenSize.small:
        return 12;
      case ScreenSize.normal:
        return 16;
      case ScreenSize.large:
        return 20;
    }
  }

  /// Font size scaled by width but clamped so text never gets illegibly
  /// small — prefer this over blanket font shrinking.
  static double font(BuildContext context, double base, {double min = 11}) {
    final scaled = scale(context, base);
    return scaled < min ? min : scaled;
  }

  /// Number of grid columns that fit a given available width for cards of
  /// [minCardWidth] logical px, clamped to [min]/[max] columns.
  static int gridColumns(
    double availableWidth, {
    double minCardWidth = 160,
    int min = 1,
    int max = 4,
  }) {
    final cols = (availableWidth / minCardWidth).floor();
    return cols.clamp(min, max);
  }

  /// Max height for a modal bottom sheet so it never exceeds the safe
  /// scrollable area, leaving room for the status bar.
  static double bottomSheetMaxHeight(BuildContext context) {
    final mq = MediaQuery.of(context);
    return mq.size.height - mq.padding.top - 24;
  }
}

/// Wraps a bottom-nav-bar (or any floating bottom element) in SafeArea and
/// keeps it clear of the device's home indicator / gesture bar.
class SafeBottomBar extends StatelessWidget {
  const SafeBottomBar({super.key, required this.child, this.margin});

  final Widget child;
  final EdgeInsets? margin;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: margin ?? EdgeInsets.zero,
      child: child,
    );
  }
}

/// A Row that automatically wraps its children onto a new line when they
/// don't fit the available width, instead of overflowing.
class ResponsiveRow extends StatelessWidget {
  const ResponsiveRow({
    super.key,
    required this.children,
    this.spacing = 8,
    this.runSpacing = 8,
    this.alignment = WrapAlignment.start,
    this.crossAxisAlignment = WrapCrossAlignment.center,
  });

  final List<Widget> children;
  final double spacing;
  final double runSpacing;
  final WrapAlignment alignment;
  final WrapCrossAlignment crossAxisAlignment;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: spacing,
      runSpacing: runSpacing,
      alignment: alignment,
      crossAxisAlignment: crossAxisAlignment,
      children: children,
    );
  }
}
