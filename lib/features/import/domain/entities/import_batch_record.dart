// lib/features/import/domain/entities/import_batch_record.dart

import 'package:equatable/equatable.dart';

import 'import_batch_report.dart';

/// A persisted import batch row loaded from the database for history display.
///
/// All fields map directly to `import_batches` columns. No Drift types leak into
/// this entity. [completedAt] is null for batches that never reached a terminal
/// state (should not normally appear in history, but guarded defensively).
class ImportBatchRecord extends Equatable {
  const ImportBatchRecord({
    required this.id,
    required this.batchCode,
    required this.sourceFolder,
    required this.status,
    required this.discoveredCount,
    required this.importedCount,
    required this.duplicateCount,
    required this.failedCount,
    required this.pairedCount,
    required this.startedAt,
    this.completedAt,
  });

  final int id;
  final String batchCode;
  final String sourceFolder;
  final ImportBatchStatus status;
  final int discoveredCount;
  final int importedCount;
  final int duplicateCount;
  final int failedCount;
  final int pairedCount;
  final DateTime startedAt;
  final DateTime? completedAt;

  @override
  List<Object?> get props => [
    id,
    batchCode,
    sourceFolder,
    status,
    discoveredCount,
    importedCount,
    duplicateCount,
    failedCount,
    pairedCount,
    startedAt,
    completedAt,
  ];
}
