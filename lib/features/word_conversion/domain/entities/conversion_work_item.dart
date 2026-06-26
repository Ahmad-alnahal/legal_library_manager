// lib/features/word_conversion/domain/entities/conversion_work_item.dart

import 'package:equatable/equatable.dart';

/// A Word conversion row that still needs operator-visible action or status.
///
/// These are not quality-review rows. They represent source Word files whose
/// conversion is pending, currently running, or previously failed.
class ConversionWorkItem extends Equatable {
  const ConversionWorkItem({
    required this.conversionId,
    required this.documentId,
    required this.sourceFileId,
    required this.sourceFileName,
    required this.sourcePath,
    required this.statusKey,
    this.errorCode,
    this.errorMessageSafe,
    required this.createdAt,
    this.updatedAt,
  });

  final int conversionId;
  final int documentId;
  final int sourceFileId;
  final String sourceFileName;
  final String sourcePath;
  final String statusKey;
  final String? errorCode;
  final String? errorMessageSafe;
  final String createdAt;
  final String? updatedAt;

  bool get canRun =>
      statusKey == 'pending_conversion' || statusKey == 'conversion_failed';

  @override
  List<Object?> get props => [
    conversionId,
    documentId,
    sourceFileId,
    sourceFileName,
    sourcePath,
    statusKey,
    errorCode,
    errorMessageSafe,
    createdAt,
    updatedAt,
  ];
}
