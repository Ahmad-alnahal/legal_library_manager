// lib/core/validation/text_normalizer.dart

/// Reusable, pure text normalization/validation primitives shared by metadata
/// validation (workflow_and_validation_spec.md §14).
///
/// These functions preserve Arabic/English Unicode; they only trim surrounding
/// whitespace and detect disallowed control characters.
abstract final class TextNormalizer {
  /// Trims surrounding whitespace and converts empty results to `null`, so an
  /// optional field left blank is stored as `null` rather than `''`.
  static String? normalizeOptional(String? raw) {
    if (raw == null) return null;
    final String trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Trims surrounding whitespace, preserving inner content. Returns `''` for a
  /// blank input (callers decide whether blank is allowed).
  static String normalizeRequired(String raw) => raw.trim();

  /// Collapses runs of ASCII whitespace to single spaces and trims. Used for
  /// keyword matching normalization.
  static String collapseWhitespace(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// Returns true if [value] contains a disallowed control character.
  ///
  /// ASCII control characters (`< 0x20`) and DEL (`0x7F`) are disallowed. When
  /// [allowLineBreaks] is true, LF (`\n`) and CR (`\r`) are permitted (for
  /// summary/review-notes free text); tabs and other control codes are not.
  static bool hasDisallowedControlChars(
    String value, {
    required bool allowLineBreaks,
  }) {
    for (final int unit in value.codeUnits) {
      if (allowLineBreaks && (unit == 0x0A || unit == 0x0D)) continue;
      if (unit < 0x20 || unit == 0x7F) return true;
    }
    return false;
  }

  /// Matches a complete ISO calendar date `YYYY-MM-DD` (with a real calendar
  /// check so e.g. `2026-02-30` is rejected).
  static bool isIsoDate(String value) {
    final RegExp shape = RegExp(r'^\d{4}-\d{2}-\d{2}$');
    if (!shape.hasMatch(value)) return false;
    final List<String> parts = value.split('-');
    final int year = int.parse(parts[0]);
    final int month = int.parse(parts[1]);
    final int day = int.parse(parts[2]);
    if (month < 1 || month > 12) return false;
    if (day < 1 || day > 31) return false;
    final DateTime parsed = DateTime(year, month, day);
    return parsed.year == year && parsed.month == month && parsed.day == day;
  }
}
