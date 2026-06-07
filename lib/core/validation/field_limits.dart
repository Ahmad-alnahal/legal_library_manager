// lib/core/validation/field_limits.dart

/// Practical maximum field lengths shared by Flutter and Drift validation
/// (workflow_and_validation_spec.md §14).
abstract final class FieldLimits {
  /// Names, titles, and entity fields.
  static const int name = 500;

  /// Stable keys and codes.
  static const int key = 100;

  /// Individual keyword display/normalized values.
  static const int keyword = 150;

  /// Summary and review-notes free text.
  static const int notes = 10000;

  /// Lowest acceptable publication year.
  static const int minPublicationYear = 1000;
}
