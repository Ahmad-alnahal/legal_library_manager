// lib/features/documents/domain/entities/draft_save_input.dart

import 'package:equatable/equatable.dart';

import 'document_aggregate.dart';
import 'document_classification_input.dart';
import 'document_common_metadata.dart';
import 'document_type_details.dart';
import 'keyword_input.dart';

/// Everything a draft-save operation persists for one document.
///
/// Any field may be incomplete (draft); validation rejects malformed entered
/// values but permits missing ones.
class DraftSaveInput extends Equatable {
  const DraftSaveInput({
    required this.documentId,
    required this.common,
    this.details,
    this.primaryClassification,
    this.additionalClassifications = const [],
    this.keywords = const [],
  });

  final int documentId;
  final DocumentCommonMetadata common;
  final DocumentTypeDetails? details;
  final DocumentClassificationInput? primaryClassification;
  final List<DocumentClassificationInput> additionalClassifications;
  final List<KeywordInput> keywords;

  /// Builds the editable draft baseline that corresponds to a persisted
  /// [DocumentAggregate]. Used by the review workflow to seed an in-memory draft
  /// and to detect unsaved changes by comparing against this baseline.
  factory DraftSaveInput.fromAggregate(DocumentAggregate aggregate) {
    return DraftSaveInput(
      documentId: aggregate.documentId,
      common: aggregate.common,
      details: aggregate.details,
      primaryClassification: aggregate.primaryClassification,
      additionalClassifications: aggregate.additionalClassifications,
      keywords: aggregate.keywords,
    );
  }

  DraftSaveInput copyWith({
    DocumentCommonMetadata? common,
    DocumentTypeDetails? details,
    DocumentClassificationInput? primaryClassification,
    List<DocumentClassificationInput>? additionalClassifications,
    List<KeywordInput>? keywords,
  }) {
    return DraftSaveInput(
      documentId: documentId,
      common: common ?? this.common,
      details: details ?? this.details,
      primaryClassification:
          primaryClassification ?? this.primaryClassification,
      additionalClassifications:
          additionalClassifications ?? this.additionalClassifications,
      keywords: keywords ?? this.keywords,
    );
  }

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
