import 'package:flutter/material.dart';

/// Centralized color tokens for MARJIY.
///
/// The palette is a calm legal/archive workstation: a light workspace with a
/// restrained navy primary and reserved blue/teal/green/amber/red accents.
/// No gradients or decorative colors are defined here on purpose.
abstract final class AppColors {
  // Workspace surfaces.
  static const Color background = Color(0xFFF4F6F9);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFF8FAFC);

  // Borders and dividers.
  static const Color border = Color(0xFFE2E8F0);
  static const Color borderStrong = Color(0xFFCBD5E1);

  // Brand / primary navy used for the header and primary actions.
  static const Color primary = Color(0xFF16314A);
  static const Color primaryHover = Color(0xFF1E4360);
  static const Color onPrimary = Color(0xFFFFFFFF);

  // Reserved teal accent for secondary emphasis.
  static const Color accentTeal = Color(0xFF0F766E);

  // Text.
  static const Color textPrimary = Color(0xFF1F2933);
  static const Color textSecondary = Color(0xFF64748B);
  static const Color textDisabled = Color(0xFF94A3B8);

  // Selected navigation surface.
  static const Color navSelected = Color(0xFFE8F0FB);
  static const Color navSelectedAccent = Color(0xFF2563EB);
}
