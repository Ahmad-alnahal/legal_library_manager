/// Centralized spacing scale (logical pixels).
///
/// Fixed values only — spacing is never derived from the viewport size so the
/// desktop layout stays stable across the supported window sizes.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Standard padding inside operational cards and panels.
  static const double cardPadding = 20;

  /// Outer padding around a page body.
  static const double pagePadding = 24;
}
