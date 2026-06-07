// lib/features/documents/domain/validation/keyword_normalizer.dart

import '../../../../core/validation/text_normalizer.dart';

/// Normalizes keyword text for matching while preserving the display value.
abstract final class KeywordNormalizer {
  /// The user-facing display value: trimmed, inner spacing/case preserved.
  static String displayOf(String raw) => TextNormalizer.normalizeRequired(raw);

  /// The matching value: trimmed, internal whitespace collapsed, lower-cased.
  /// Lower-casing is a no-op for Arabic script but unifies Latin keywords, so
  /// matching is consistent across both.
  static String normalizedOf(String raw) =>
      TextNormalizer.collapseWhitespace(raw).toLowerCase();
}
