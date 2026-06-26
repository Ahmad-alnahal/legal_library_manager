// lib/features/word_conversion/domain/entities/conversion_review_item.dart

import 'package:equatable/equatable.dart';

/// A single entry in the conversion-quality review queue.
///
/// Carries enough information for the reviewer to identify the source Word
/// document, locate the generated PDF, and act on the review. All paths are
/// stored exactly as recorded in [document_files]; no filesystem access occurs
/// when building this entity.
class ConversionReviewItem extends Equatable {
  const ConversionReviewItem({
    required this.conversionId,
    required this.documentId,
    required this.sourceFileId,
    required this.outputFileId,
    required this.sourceFileName,
    required this.sourcePath,
    required this.outputFileName,
    required this.outputPath,
    this.converterKey,
    this.completedAt,
    required this.createdAt,
  });

  final int conversionId;
  final int documentId;

  /// The `document_files.id` of the original Word source (role: source_original).
  final int sourceFileId;

  /// The `document_files.id` of the generated PDF (role: converted_pdf).
  final int outputFileId;

  final String sourceFileName;
  final String sourcePath;
  final String outputFileName;
  final String outputPath;
  final String? converterKey;

  /// UTC ISO-8601 timestamp when the conversion process completed.
  final String? completedAt;

  /// UTC ISO-8601 timestamp when the conversion record was created.
  final String createdAt;

  @override
  List<Object?> get props => [
    conversionId,
    documentId,
    sourceFileId,
    outputFileId,
    sourceFileName,
    sourcePath,
    outputFileName,
    outputPath,
    converterKey,
    completedAt,
    createdAt,
  ];
}
