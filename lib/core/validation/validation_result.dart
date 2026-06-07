// lib/core/validation/validation_result.dart

import 'package:equatable/equatable.dart';

import 'validation_error.dart';

/// The structured outcome of a validation pass: a (possibly empty) list of
/// [ValidationError]s. Empty means valid. Suitable for future Arabic UI display
/// because every error carries a stable field path and machine code.
class ValidationResult extends Equatable {
  const ValidationResult(this.errors);

  const ValidationResult.valid() : errors = const [];

  final List<ValidationError> errors;

  bool get isValid => errors.isEmpty;
  bool get isInvalid => errors.isNotEmpty;

  /// True when any error targets [field].
  bool hasError(String field) => errors.any((e) => e.field == field);

  /// True when any error carries [code].
  bool hasCode(String code) => errors.any((e) => e.code == code);

  @override
  List<Object?> get props => [errors];

  @override
  String toString() =>
      isValid ? 'ValidationResult.valid' : 'ValidationResult($errors)';
}

/// Mutable accumulator for building a [ValidationResult].
class ValidationErrorBuilder {
  final List<ValidationError> _errors = [];

  bool get hasErrors => _errors.isNotEmpty;

  void add(String field, String code, String message) =>
      _errors.add(ValidationError(field: field, code: code, message: message));

  void addError(ValidationError error) => _errors.add(error);

  void addAll(Iterable<ValidationError> errors) => _errors.addAll(errors);

  ValidationResult build() => ValidationResult(List.unmodifiable(_errors));
}
