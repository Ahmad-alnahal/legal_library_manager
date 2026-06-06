import 'package:flutter/material.dart';

/// A foreground/background pair for a status indicator (chip, metric accent…).
@immutable
class StatusColor {
  const StatusColor({required this.foreground, required this.background});

  final Color foreground;
  final Color background;
}

/// Centralized status colors used for metric accents, chips and indicators.
///
/// Each status pairs a saturated foreground with a soft tinted background so
/// status reads clearly against the light workspace without shouting.
abstract final class AppStatusColors {
  /// Neutral/total — used for "total imported" style metrics.
  static const StatusColor neutral = StatusColor(
    foreground: Color(0xFF334155),
    background: Color(0xFFEEF1F5),
  );

  /// Informational (in progress).
  static const StatusColor info = StatusColor(
    foreground: Color(0xFF2563EB),
    background: Color(0xFFEFF4FF),
  );

  /// Success (classified / copied / verified).
  static const StatusColor success = StatusColor(
    foreground: Color(0xFF15803D),
    background: Color(0xFFE9F6EF),
  );

  /// Warning (needs review).
  static const StatusColor warning = StatusColor(
    foreground: Color(0xFFB45309),
    background: Color(0xFFFCF3E6),
  );

  /// Danger (corrupted / unreadable).
  static const StatusColor danger = StatusColor(
    foreground: Color(0xFFB91C1C),
    background: Color(0xFFFCEDED),
  );

  /// Duplicate groups.
  static const StatusColor duplicate = StatusColor(
    foreground: Color(0xFF5B53C7),
    background: Color(0xFFEEEDFB),
  );

  /// Teal accent (ready-for-export / local export readiness).
  static const StatusColor teal = StatusColor(
    foreground: Color(0xFF0F766E),
    background: Color(0xFFE6F4F2),
  );
}
