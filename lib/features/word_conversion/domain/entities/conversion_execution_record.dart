// lib/features/word_conversion/domain/entities/conversion_execution_record.dart

import 'package:equatable/equatable.dart';

/// Safe projection of a `file_conversions` row for the conversion use case.
///
/// Returned by [WordConversionRepository.loadConversionForExecution]. Carries
/// only the fields needed to execute and finalize a conversion. No Drift types
/// leak into this class.
class ConversionExecutionRecord extends Equatable {
  const ConversionExecutionRecord({
    required this.conversionId,
    required this.documentId,
    required this.sourceFileId,
    required this.statusKey,
    this.converterKey,
  });

  final int conversionId;
  final int documentId;

  /// FK to `document_files.id` — the Word source_original file.
  final int sourceFileId;

  /// Current `file_conversions.status_key`.
  final String statusKey;

  /// `file_conversions.converter_key`, e.g. `microsoft_word`.
  final String? converterKey;

  @override
  List<Object?> get props => [
    conversionId,
    documentId,
    sourceFileId,
    statusKey,
    converterKey,
  ];
}
