// lib/features/import/domain/entities/import_batch_report.dart

import 'package:equatable/equatable.dart';

import 'import_file_result.dart';

/// A reference to a persisted import batch.
class ImportBatchRef extends Equatable {
  const ImportBatchRef({required this.id, required this.batchCode});

  final int id;
  final String batchCode;

  @override
  List<Object?> get props => [id, batchCode];
}

/// Lifecycle states for an import batch (`import_batches.status_key`).
///
/// The schema places no CHECK on this column; these are the keys this engine
/// uses. The orchestration (M4.2) transitions a batch through them.
enum ImportBatchStatus {
  running('running'),
  completed('completed'),
  failed('failed'),
  cancelled('cancelled');

  const ImportBatchStatus(this.key);

  final String key;
}

/// A summary/report of a completed import batch.
///
/// Counts are derived from per-file outcomes; [results] is the full ordered list
/// of per-file outcomes for the report UI (built in M4.2).
class ImportBatchSummary extends Equatable {
  const ImportBatchSummary({
    required this.batch,
    required this.status,
    required this.results,
  });

  factory ImportBatchSummary.fromResults({
    required ImportBatchRef batch,
    required ImportBatchStatus status,
    required List<ImportFileResult> results,
  }) {
    return ImportBatchSummary(batch: batch, status: status, results: results);
  }

  final ImportBatchRef batch;
  final ImportBatchStatus status;
  final List<ImportFileResult> results;

  int get discoveredCount => results.length;

  int countOf(ImportFileOutcome outcome) =>
      results.where((r) => r.outcome == outcome).length;

  /// Newly created plus duplicate-path imports.
  int get importedCount =>
      countOf(ImportFileOutcome.importedNew) +
      countOf(ImportFileOutcome.importedDuplicatePath);

  int get duplicateCount => countOf(ImportFileOutcome.importedDuplicatePath);

  /// Every non-success outcome counts as a failure for the batch counters.
  int get failedCount =>
      countOf(ImportFileOutcome.unreadable) +
      countOf(ImportFileOutcome.hashFailed) +
      countOf(ImportFileOutcome.scanFailed) +
      countOf(ImportFileOutcome.unsupportedType);

  int get alreadyImportedCount => countOf(ImportFileOutcome.alreadyImported);

  @override
  List<Object?> get props => [batch, status, results];
}
