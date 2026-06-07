// lib/features/documents/domain/entities/normalized_draft.dart

import 'package:equatable/equatable.dart';

import 'document_classification_input.dart';
import 'document_common_metadata.dart';
import 'document_type_details.dart';

/// A [DraftSaveInput] after normalization: trimmed text, empty→null optionals,
/// and keywords reduced to unique normalized entries. This is the shape the
/// repository persists.
class NormalizedDraft extends Equatable {
  const NormalizedDraft({
    required this.documentId,
    required this.common,
    required this.details,
    required this.primaryClassification,
    required this.additionalClassifications,
    required this.keywords,
  });

  final int documentId;
  final DocumentCommonMetadata common;
  final DocumentTypeDetails? details;
  final DocumentClassificationInput? primaryClassification;
  final List<DocumentClassificationInput> additionalClassifications;
  final List<NormalizedKeyword> keywords;

  @override
  List<Object?> get props => [
    documentId,
    common,
    details,
    primaryClassification,
    additionalClassifications,
    keywords,
  ];
}

/// A keyword after normalization: user-facing [displayValue] plus the
/// [normalizedValue] used for matching/reuse.
class NormalizedKeyword extends Equatable {
  const NormalizedKeyword({
    required this.displayValue,
    required this.normalizedValue,
    this.languageKey,
  });

  final String displayValue;
  final String normalizedValue;
  final String? languageKey;

  @override
  List<Object?> get props => [displayValue, normalizedValue, languageKey];
}
