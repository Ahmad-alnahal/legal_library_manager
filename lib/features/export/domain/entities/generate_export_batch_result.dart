// lib/features/export/domain/entities/generate_export_batch_result.dart

import 'package:equatable/equatable.dart';

/// One document excluded from a batch, with a safe, stable reason.
class ExportSkipEntry extends Equatable {
  const ExportSkipEntry({required this.documentCode, required this.reason});

  final String documentCode;
  final String reason;

  @override
  List<Object?> get props => [documentCode, reason];
}

/// One included document whose usage rights require manual attention.
class ExportFlaggedEntry extends Equatable {
  const ExportFlaggedEntry({
    required this.documentCode,
    required this.usageRightsKey,
  });

  final String documentCode;
  final String usageRightsKey;

  @override
  List<Object?> get props => [documentCode, usageRightsKey];
}

/// Outcome of [GenerateExportBatch] (workflow_and_validation_spec.md §11).
sealed class GenerateExportBatchResult extends Equatable {
  const GenerateExportBatchResult();
}

/// The batch was created, verified end-to-end, and marked `verified`.
class GenerateExportBatchSuccess extends GenerateExportBatchResult {
  const GenerateExportBatchSuccess({
    required this.batchCode,
    required this.exportPath,
    required this.includedCount,
    required this.skippedCount,
    required this.skippedReasons,
    required this.flaggedUsageRights,
  });

  final String batchCode;
  final String exportPath;
  final int includedCount;
  final int skippedCount;
  final List<ExportSkipEntry> skippedReasons;
  final List<ExportFlaggedEntry> flaggedUsageRights;

  @override
  List<Object?> get props => [
    batchCode,
    exportPath,
    includedCount,
    skippedCount,
    skippedReasons,
    flaggedUsageRights,
  ];
}

/// No document was in `ready_for_export` at the start of the run.
class GenerateExportBatchNothingToExport extends GenerateExportBatchResult {
  const GenerateExportBatchNothingToExport();

  @override
  List<Object?> get props => [];
}

/// Every ready document failed managed-file verification; no batch created.
class GenerateExportBatchAllSkipped extends GenerateExportBatchResult {
  const GenerateExportBatchAllSkipped({required this.skippedReasons});

  final List<ExportSkipEntry> skippedReasons;

  @override
  List<Object?> get props => [skippedReasons];
}

/// The run could not complete. [batchCode]/[exportPath] are null when no
/// batch record was ever created; otherwise the batch was finalized `failed`
/// and its partial folder was left in place for inspection.
class GenerateExportBatchFailed extends GenerateExportBatchResult {
  const GenerateExportBatchFailed({
    required this.safeMessage,
    this.batchCode,
    this.exportPath,
  });

  final String safeMessage;
  final String? batchCode;
  final String? exportPath;

  @override
  List<Object?> get props => [safeMessage, batchCode, exportPath];
}
