// lib/features/import/application/import_run_report.dart

import 'package:equatable/equatable.dart';

import '../domain/entities/folder_validation.dart';
import '../domain/entities/import_batch_report.dart';
import 'import_file_report.dart';

/// The ordered outcome of an import run (or retry).
///
/// [batch] is null only when folder validation failed before any batch was
/// created. [files] preserves deterministic discovery order. Counts are derived.
class ImportRunReport extends Equatable {
  const ImportRunReport({
    required this.status,
    required this.files,
    this.batch,
    this.validation,
    this.discoveredTotal,
  });

  /// A pre-batch validation failure (no batch created, no files processed).
  factory ImportRunReport.validationFailed(FolderValidationResult validation) {
    return ImportRunReport(
      status: ImportBatchStatus.failed,
      files: const [],
      validation: validation,
    );
  }

  final ImportBatchStatus status;
  final List<ImportFileReport> files;
  final ImportBatchRef? batch;
  final FolderValidationResult? validation;

  /// The full number of entries discovered by scanning, retained even when a
  /// run was cancelled after processing only some of them. Falls back to the
  /// processed count when not explicitly provided.
  final int? discoveredTotal;

  int get discoveredCount => discoveredTotal ?? files.length;

  int countOf(ImportFileStatus status) =>
      files.where((f) => f.status == status).length;

  int get importedNewCount => countOf(ImportFileStatus.importedNew);
  int get duplicateCount => countOf(ImportFileStatus.importedDuplicatePath);
  int get alreadyImportedCount => countOf(ImportFileStatus.alreadyImported);

  int get importedCount => importedNewCount + duplicateCount;

  int get failedCount => files.where((f) => f.status.isFailure).length;

  List<ImportFileReport> get retryableFiles =>
      files.where((f) => f.isRetryable).toList();

  bool get hasRetryableFailures => retryableFiles.isNotEmpty;

  @override
  List<Object?> get props => [
    status,
    files,
    batch,
    validation,
    discoveredCount,
  ];
}
