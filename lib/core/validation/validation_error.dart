// lib/core/validation/validation_error.dart

import 'package:equatable/equatable.dart';

/// A single structured, machine-readable validation failure.
///
/// [field] is a stable path (e.g. `title`, `book.author`, `primaryClassification`)
/// and [code] is a stable machine code (e.g. `required`, `too_long`,
/// `invalid_reference`). The Arabic UI maps `(field, code)` to localized text
/// later; [message] is a developer-facing English description only.
class ValidationError extends Equatable {
  const ValidationError({
    required this.field,
    required this.code,
    required this.message,
  });

  final String field;
  final String code;
  final String message;

  @override
  List<Object?> get props => [field, code, message];

  @override
  String toString() => 'ValidationError($field, $code, "$message")';
}
