// lib/features/managed_copy/domain/repositories/managed_copy_repository.dart

import '../entities/copy_roots.dart';
import '../entities/document_copy_state.dart';
import '../entities/managed_copy_persistence_data.dart';
import '../entities/managed_file_ref.dart';
import '../entities/source_file_candidate.dart';
import '../entities/startup_recovery_report.dart';

/// Persistence boundary for the managed-copy workflow.
///
/// Implementations may import Drift and dart:io. Domain and application layers
/// depend only on this abstraction. Source file records must never be mutated
/// or deleted through any method on this interface.
abstract class ManagedCopyRepository {
  /// Loads the document's current copy-readiness state.
  ///
  /// Returns null when no document with [documentId] exists.
  Future<DocumentCopyState?> loadDocumentState(int documentId);

  /// Loads managed_library_root and database_backup_root from settings.
  Future<CopyRoots> loadCopyRoots();

  /// Atomically stores the validated managed-library and backup roots.
  Future<void> saveCopyRoots({
    required String managedLibraryRoot,
    required String backupRoot,
  }) => throw UnimplementedError('Copy-root persistence is not implemented.');

  /// Returns the application-support directory path (where the SQLite DB lives).
  Future<String> loadDatabaseRoot();

  /// Returns absolute_path values for all source_original files belonging to
  /// [documentId]. Used for root-overlap safety validation.
  Future<List<String>> loadDocumentSourcePaths(int documentId);

  /// Returns every registered original-source path for settings-level root
  /// validation.
  Future<List<String>> loadAllSourcePaths() async => const [];

  /// Returns assigned document codes used to identify MARJIY-owned managed
  /// files during startup inspection. Implementations should return only
  /// non-null codes already persisted in the database.
  Future<List<String>> loadManagedDocumentCodes() async => const [];

  /// Persists the latest startup recovery inspection result as safe settings
  /// metadata. This is intentionally coarse; it never stores file contents.
  Future<void> saveStartupRecoveryReport(StartupRecoveryReport report) =>
      throw UnimplementedError(
        'Startup recovery persistence is not implemented.',
      );

  /// Loads the latest startup recovery inspection result.
  Future<StartupRecoveryReport> loadStartupRecoveryReport() async =>
      StartupRecoveryReport.healthy;

  /// Returns source_original candidate files for [documentId].
  ///
  /// Returns only rows where file_role_key = 'source_original'. The use case
  /// applies its own eligibility filters (health, extension, existence).
  Future<List<SourceFileCandidate>> loadEligibleSources(int documentId);

  /// Transactionally assigns a document code to [documentId] if none exists.
  ///
  /// Returns the (newly assigned or already existing) code. The next code is
  /// derived from the maximum existing code number — never from row count.
  /// Concurrent allocations are serialized by the surrounding transaction.
  Future<String> allocateDocumentCode(int documentId);

  /// Appends a single row to file_events.
  ///
  /// All string parameters must be safe values (stable codes, paths, short
  /// messages) — never raw exception text or document contents.
  Future<void> appendFileEvent({
    required int? documentId,
    required int? fileId,
    required String eventTypeKey,
    required String operationId,
    required String resultKey,
    String? sourcePath,
    String? destinationPath,
    String? expectedSha256,
    String? actualSha256,
    String? errorCode,
    String? messageSafe,
  });

  /// Atomically writes the managed-copy success state in one transaction:
  ///
  /// 1. Inserts the managed_copy document_files row.
  /// 2. Appends copy_completed and copy_verified file_events.
  /// 3. Updates documents.workflow_status_key to 'copied_to_library',
  ///    copied_to_library_at, and updated_at.
  ///
  /// Returns the new document_files.id. Throws on any failure so the caller
  /// can detect that persistence did not succeed.
  ///
  /// Allows re-copy when all existing managed-copy rows have
  /// file_health_key = 'missing'. Blocks when any healthy managed copy exists.
  Future<int> persistManagedCopySuccess(ManagedCopyPersistenceData data);

  // ── M8.6: Missing-file reconciliation ──────────────────────────────────────

  /// Returns all document_files rows with file_role_key = 'managed_copy' for
  /// [documentId], in any health state.
  Future<List<ManagedFileRef>> loadManagedCopyFiles(int documentId);

  /// Marks a single managed-copy file row as physically missing (M8.6).
  ///
  /// 1. Updates document_files.file_health_key to 'missing' for [fileId].
  /// 2. Appends a 'marked_missing' file_event with result_key = 'warning'.
  ///
  /// The file row is preserved in full — no deletion. Source files are never
  /// touched by this method.
  Future<void> markManagedFileMissing({
    required int fileId,
    required int documentId,
    required String operationId,
    required DateTime now,
  });

  /// Marks a previously-missing managed-copy file as healthy again after the
  /// application has verified that the restored physical file matches the
  /// stored DB metadata (size and SHA-256).
  ///
  /// Also appends an 'existence_checked' file_event and restores the document
  /// workflow to 'copied_to_library'. Source files are never touched.
  Future<void> restoreManagedFileHealthy({
    required int fileId,
    required int documentId,
    required String operationId,
    required DateTime now,
  });

  /// Downgrades [documentId] workflow status from 'copied_to_library' back to
  /// 'classified' (M8.6 reconciliation).
  ///
  /// This is the only situation where workflow_status_key moves backwards.
  /// The operation is idempotent: if the document is already 'classified'
  /// it succeeds silently.
  Future<void> downgradeDocumentToClassified({
    required int documentId,
    required DateTime now,
  });
}
