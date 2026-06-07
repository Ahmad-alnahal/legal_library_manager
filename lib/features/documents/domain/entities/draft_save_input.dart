// lib/features/documents/domain/entities/draft_save_input.dart

import 'package:equatable/equatable.dart';

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
