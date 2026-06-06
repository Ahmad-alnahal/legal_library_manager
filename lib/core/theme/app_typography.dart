import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Centralized typography.
///
/// Uses fixed font sizes (never viewport-scaled) and the platform default
/// font, which renders Arabic clearly on Windows. Headings are restrained — no
/// oversized marketing headlines.
abstract final class AppTypography {
  static const String? _fontFamily = null; // platform default (Segoe UI).

  static const TextTheme textTheme = TextTheme(
    // Page titles.
    headlineSmall: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 22,
      height: 1.3,
      fontWeight: FontWeight.w700,
      color: AppColors.textPrimary,
    ),
    titleLarge: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 18,
      height: 1.35,
      fontWeight: FontWeight.w600,
      color: AppColors.textPrimary,
    ),
    titleMedium: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 15,
      height: 1.35,
      fontWeight: FontWeight.w600,
      color: AppColors.textPrimary,
    ),
    bodyLarge: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 14,
      height: 1.45,
      fontWeight: FontWeight.w400,
      color: AppColors.textPrimary,
    ),
    bodyMedium: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 13,
      height: 1.45,
      fontWeight: FontWeight.w400,
      color: AppColors.textSecondary,
    ),
    labelLarge: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 13,
      height: 1.2,
      fontWeight: FontWeight.w600,
      color: AppColors.textPrimary,
    ),
    labelMedium: TextStyle(
      fontFamily: _fontFamily,
      fontSize: 12,
      height: 1.2,
      fontWeight: FontWeight.w500,
      color: AppColors.textSecondary,
    ),
  );

  /// Large numeric value used inside operational metric cards.
  static const TextStyle metricValue = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 26,
    height: 1.1,
    fontWeight: FontWeight.w700,
    color: AppColors.textPrimary,
  );
}
