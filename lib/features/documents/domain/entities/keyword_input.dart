// lib/features/documents/domain/entities/keyword_input.dart

import 'package:equatable/equatable.dart';

/// A keyword to associate with a document.
///
/// [displayValue] is the user-facing text (trimmed, case/spacing preserved).
/// [languageKey] is optional. The matching/normalized value is derived during
/// normalization and used to reuse existing keyword rows and prevent duplicate
/// links.
class KeywordInput extends Equatable {
  const KeywordInput({required this.displayValue, this.languageKey});

  final String displayValue;
  final String? languageKey;

  @override
  List<Object?> get props => [displayValue, languageKey];
}
