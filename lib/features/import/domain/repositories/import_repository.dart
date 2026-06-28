// lib/features/import/domain/repositories/import_repository.dart

import '../entities/import_batch_record.dart';
import '../entities/import_batch_report.dart';
import '../entities/import_file_result.dart';
import '../entities/prepared_source_file.dart';

/// Persistence-agnostic contract for import persistence: batch lifecycle,
/// transactional per-file identity/duplicate resolution, and safe audit events.
///
/// Implementations confine all Drift types to the data layer. Every per-file
/// method persists that file's document/file/duplicate/event rows in a single
/// transaction; a failure rolls back only that file's partial changes and never
/// touches prior successful files. No method ever copies, moves, renames,
/// deletes, or writes a source file.
abstract class ImportRepository {
  // --- Batch lifecycle primitives (M4.2 drives these) ---

  /// Creates a batch row with a unique, stable batch code in status `running`.
  Future<ImportBatchRef> createBatch({
    required String sourceFolder,
    required bool recursive,
    required DateTime now,
  });

  /// Updates batch counters and (optionally) status. When [clearCompletedAt] is
  /// true, the terminal completion timestamp is reset to null — used when a
  /// retry reopens a finished batch back to `running`.
  Future<void> updateBatchProgress(
    int batchId, {
    int? discoveredCount,
    int? importedCount,
    int? duplicateCount,
    int? failedCount,
    int? pairedCount,
    ImportBatchStatus? status,
    bool clearCompletedAt = false,
  });

  /// Marks a batch `completed` with final counters and a completion timestamp.
  Future<void> completeBatch(
    int batchId, {
    required int discoveredCount,
    required int importedCount,
    required int duplicateCount,
    required int failedCount,
    required int pairedCount,
    required DateTime now,
  });

  /// Marks every batch currently in `running` state as `interrupted`.
  ///
  /// Called once at application startup to clean up any batch that was active
  /// when the process was killed or crashed. Full resume behaviour is deferred
  /// to P2.3; for now this ensures no batch is permanently stuck in `running`.
  Future<void> markInterruptedBatches({required DateTime now});

  /// Marks a batch `failed` with a completion timestamp.
  Future<void> failBatch(int batchId, {required DateTime now});

  /// Marks a batch `cancelled` with a completion timestamp.
  Future<void> cancelBatch(int batchId, {required DateTime now});

  // --- History ---

  /// Returns up to [limit] import batches ordered newest-first (by started_at).
  Future<List<ImportBatchRecord>> getRecentBatches({int limit = 20});

  // --- Identity lookup ---

  /// Returns the existing file matched by [canonicalPath] using Windows
  /// case-insensitive identity, or `null` when the path is not yet imported.
  Future<ExistingFileRef?> findByAbsolutePath(String canonicalPath);

  // --- Transactional per-file persistence ---

  /// Persists a successfully hashed file transactionally and assigns its
  /// outcome:
  ///
  /// - same absolute path already imported -> updates last-checked metadata only
  ///   and returns `already_imported`;
  /// - new SHA-256 -> creates one document and one `source_original` file row,
  ///   returns `imported_new`;
  /// - existing SHA-256 at a different path -> attaches a new `source_original`
  ///   row to the existing document, creates/updates exactly one duplicate group
  ///   containing every matching physical file, returns
  ///   `imported_duplicate_path`.
  ///
  /// Records the appropriate safe import/file events. When [batchId] is given,
  /// also attaches an `import_batch_files` result row for the file.
  Future<ImportFileResult> persistHashedFile(
    PreparedSourceFile file, {
    required String operationId,
    required DateTime now,
    int? batchId,
  });

  /// Persists a hash-failed / unreadable file transactionally. Retains the
  /// physical source record (creating the minimum logical document it requires),
  /// marks health `unreadable`/`corrupted`, stores a `null` SHA-256, never joins
  /// a duplicate group, and records a safe failure event. Returns `hash_failed`
  /// or `unreadable` per [outcome]. A same-path match short-circuits to
  /// `already_imported`.
  Future<ImportFileResult> persistFailedFile(
    FailedSourceFile file, {
    required ImportFileOutcome outcome,
    required String operationId,
    required DateTime now,
    int? batchId,
  });

  /// Records a safe, file-less event for outcomes with no file row
  /// (`scan_failed`, `unsupported_type`). Returns the given [outcome] result.
  Future<ImportFileResult> recordFilelessOutcome({
    required ImportFileOutcome outcome,
    required String sourcePath,
    required String operationId,
    required DateTime now,
    String? errorCode,
    String? safeMessage,
  });

  /// Persists a paired `.doc` source file on an existing document (the one that
  /// owns the paired `.pdf`). Hashes, creates a `source_original` file row on
  /// [existingDocumentId], and records a `paired_source_detected` audit event.
  /// No new document row is created. A same-path match short-circuits to
  /// `already_imported`. When [batchId] is given, attaches an
  /// `import_batch_files` result row.
  Future<ImportFileResult> persistPairedWordSource(
    PreparedSourceFile file, {
    required int existingDocumentId,
    required String operationId,
    required DateTime now,
    int? batchId,
  });
}
