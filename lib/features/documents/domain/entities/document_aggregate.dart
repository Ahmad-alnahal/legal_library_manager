// lib/features/documents/domain/entities/document_aggregate.dart

import 'package:equatable/equatable.dart';

import 'document_classification_input.dart';
import 'document_common_metadata.dart';
import 'document_conversion_ref.dart';
import 'document_file_ref.dart';
import 'document_type_details.dart';
import 'keyword_input.dart';

/// A complete, persisted snapshot of a document's metadata, assembled from the
/// documents row, its matching type-detail row, classifications, keyword links,
/// physical files, and conversions. Used by classification validation/approval.
class DocumentAggregate extends Equatable {
  const DocumentAggregate({
    required this.documentId,
    required this.workflowStatusKey,
    required this.common,
    required this.details,
    required this.primaryClassification,
    required this.additionalClassifications,
    required this.keywords,
    required this.files,
    required this.conversions,
    this.documentCode,
    this.classifiedAt,
  });

  final int documentId;
  final String workflowStatusKey;
  final DocumentCommonMetadata common;

  /// The matching type-detail object, or `null` for `other`/no-detail drafts.
  final DocumentTypeDetails? details;

  final DocumentClassificationInput? primaryClassification;
  final List<DocumentClassificationInput> additionalClassifications;
  final List<KeywordInput> keywords;
  final List<DocumentFileRef> files;
  final List<DocumentConversionRef> conversions;

  final String? documentCode;
  final String? classifiedAt;

  @override
  List<Object?> get props => [
    documentId,
    workflowStatusKey,
    common,
    details,
    primaryClassification,
    additionalClassifications,
    keywords,
    files,
    conversions,
    documentCode,
    classifiedAt,
  ];
}
