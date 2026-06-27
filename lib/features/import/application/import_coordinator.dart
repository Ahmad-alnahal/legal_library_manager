// lib/features/import/application/import_coordinator.dart

import 'dart:async';
import 'dart:isolate';

import '../../../core/time/clock.dart';
import '../domain/entities/folder_validation.dart';
import '../domain/entities/import_batch_report.dart';
import '../domain/entities/import_error.dart';
import '../domain/entities/import_file_result.dart';
import '../domain/entities/import_request.dart';
import '../domain/entities/pdf_candidate.dart';
import '../domain/entities/pdf_health_result.dart';
import '../domain/entities/prepared_source_file.dart';
import '../domain/entities/sha256_result.dart';
import '../domain/repositories/import_repository.dart';
import '../domain/services/file_hasher.dart';
import '../domain/services/folder_validator.dart';
import '../domain/services/pdf_health_inspector.dart';
import '../domain/services/pdf_scanner.dart';
import 'import_file_report.dart';
import 'import_progress.dart';
import 'import_run_report.dart';

/// Runs a computation on a background isolate. Injectable so tests can run work
/// synchronously with fakes (which are not sendable across isolates).
typedef IsolateRunner = Future<T> Function<T>(FutureOr<T> Function() body);

/// Default production runner: executes [body] on a fresh background isolate so
/// folder scanning and PDF inspection never block the Flutter UI isolate.
Future<T> isolateRunner<T>(FutureOr<T> Function() body) => Isolate.run(body);

const String _pdfMimeType = 'application/pdf';
const String _docMimeType = 'application/msword';

/// Application-layer orchestrator for the safe PDF import workflow.
///
/// Validates the source folder, creates and finalizes the persisted import
/// batch, scans and inspects PDFs off the UI isolate, hashes via the
/// worker-isolate [FileHasher], and persists each file transactionally — never
/// copying, writing, moving, renaming, deleting, or modifying source files.
/// Processing is sequential for predictable database writes and cancellation,
/// continues past individual failures, emits live progress, supports cooperative
/// cancellation, and supports retrying only retryable failures.
class ImportCoordinator {
  ImportCoordinator({
    required this.validator,
    required this.scanner,
    required this.hasher,
    required this.inspector,
    required this.repository,
    required this.clock,
    this.runner = isolateRunner,
  });

  final FolderValidator validator;
  final PdfScanner scanner;
  final FileHasher hasher;
  final PdfHealthInspector inspector;
  final ImportRepository repository;
  final Clock clock;
  final IsolateRunner runner;

  /// Runs a full import for [request].
  ///
  /// [cancellation] is polled between files and passed to the hasher;
  /// [onProgress] receives live phase/progress updates.
  Future<ImportRunReport> run(
    ImportRequest request, {
    required HashCancellation cancellation,
    void Function(ImportProgress progress)? onProgress,
  }) async {
    onProgress?.call(const ImportProgress(phase: ImportPhase.validating));

    final FolderValidationResult validation = await validator.validate(
      request.sourceFolder,
      protectedRoots: request.protectedRoots,
    );
    if (!validation.isValid) {
      return ImportRunReport.validationFailed(validation);
    }

    final ImportBatchRef batch = await repository.createBatch(
      sourceFolder: validation.canonicalPath ?? request.sourceFolder,
      recursive: request.recursive,
      now: clock.nowUtc(),
    );

    // Declared outside the try so an unexpected coordinator-level failure can
    // still return the reports already produced (and the true discovered count)
    // instead of discarding earlier successes with an empty report.
    final List<ImportFileReport> reports = [];
    int discovered = 0;
    try {
      onProgress?.call(const ImportProgress(phase: ImportPhase.scanning));
      // Bind to a local so the isolate closure captures only the (sendable)
      // const scanner and request — never `this` (which holds the database).
      final PdfScanner scannerService = scanner;
      final PdfScanResult scan = await runner<PdfScanResult>(
        () => scannerService.scan(request),
      );

      discovered = scan.candidates.length + scan.failures.length;
      await repository.updateBatchProgress(
        batch.id,
        discoveredCount: discovered,
      );

      int processed = 0;
      bool cancelled = false;

      // Directory-enumeration failures first (file-less scan failures).
      for (final PdfScanFailure failure in scan.failures) {
        if (cancellation.isCancelled) {
          cancelled = true;
          break;
        }
        onProgress?.call(
          ImportProgress(
            phase: ImportPhase.importing,
            processed: processed,
            discovered: discovered,
            currentFileName: failure.path,
          ),
        );
        reports.add(await _recordScanFailure(failure, batch, processed));
        processed++;
      }

      if (!cancelled) {
        // Detect same-folder same-basename .doc+.pdf pairs. Paired .docs are
        // moved to the end of the processing order so their PDF has already been
        // imported (and its documentId is available) by the time the .doc runs.
        final Set<String> pairedKeys = _detectPairedKeys(scan.candidates);
        final List<PdfCandidate> ordered = _orderWithPairedDocsLast(
          scan.candidates,
          pairedKeys,
        );
        // Maps a pair key to the document ID of the successfully imported PDF,
        // so the paired .doc can attach itself to the same document.
        final Map<String, int> pairedPdfDocIds = {};

        for (final PdfCandidate candidate in ordered) {
          if (cancellation.isCancelled) {
            cancelled = true;
            break;
          }
          onProgress?.call(
            ImportProgress(
              phase: ImportPhase.importing,
              processed: processed,
              discovered: discovered,
              currentFileName: candidate.fileName,
            ),
          );

          final String pKey = _pairKey(candidate);
          late final _FileOutcome outcome;

          if (_isWordSource(candidate.extension) && pairedKeys.contains(pKey)) {
            final int? pairedDocId = pairedPdfDocIds[pKey];
            if (pairedDocId != null) {
              // PDF imported successfully — attach .doc to the same document.
              outcome = await _processPairedWordCandidate(
                candidate,
                existingDocumentId: pairedDocId,
                batchId: batch.id,
                cancellation: cancellation,
                operationId: _operationId(batch, processed),
              );
            } else {
              // PDF failed to import — fall back to the regular word flow.
              outcome = await _processWordCandidate(
                candidate,
                batchId: batch.id,
                cancellation: cancellation,
                operationId: _operationId(batch, processed),
              );
            }
          } else {
            outcome = await _processCandidate(
              candidate,
              batchId: batch.id,
              cancellation: cancellation,
              operationId: _operationId(batch, processed),
            );
            // Track the document ID only when the PDF imported successfully.
            if (!_isWordSource(candidate.extension) &&
                pairedKeys.contains(pKey)) {
              final ImportFileStatus? status = outcome.report?.status;
              if (status != null && !status.isFailure) {
                final int? docId = outcome.report?.documentId;
                if (docId != null) pairedPdfDocIds[pKey] = docId;
              }
            }
          }

          if (outcome.cancelled) {
            cancelled = true;
            break;
          }
          reports.add(outcome.report!);
          processed++;
        }
      }

      onProgress?.call(
        ImportProgress(
          phase: ImportPhase.finalizing,
          processed: processed,
          discovered: discovered,
        ),
      );
      // Awaited so a failure inside finalization is caught here and preserves
      // the reports already produced, rather than escaping to the caller.
      return await _finalize(
        batch,
        reports,
        cancelled: cancelled,
        discovered: discovered,
      );
    } catch (_) {
      // Unexpected coordinator-level failure: fail the batch safely (best-
      // effort), never leaving it stuck "running". Preserve already-produced
      // reports and the true discovered count. No exception details are surfaced.
      await _failBatchSafely(batch.id);
      return ImportRunReport(
        status: ImportBatchStatus.failed,
        files: List<ImportFileReport>.unmodifiable(reports),
        batch: batch,
        discoveredTotal: discovered,
      );
    }
  }

  /// Re-attempts only the retryable failures in [previous], reusing the same
  /// batch and leaving already-successful files untouched.
  Future<ImportRunReport> retry(
    ImportRunReport previous, {
    required HashCancellation cancellation,
    void Function(ImportProgress progress)? onProgress,
  }) async {
    final ImportBatchRef? batch = previous.batch;
    if (batch == null || !previous.hasRetryableFailures) {
      return previous;
    }

    onProgress?.call(const ImportProgress(phase: ImportPhase.validating));
    // Reopen the batch: back to running and clear the prior terminal timestamp,
    // so a fresh completed_at is only set when this retry itself finishes.
    await repository.updateBatchProgress(
      batch.id,
      status: ImportBatchStatus.running,
      clearCompletedAt: true,
    );

    final List<ImportFileReport> retryable = previous.retryableFiles;
    final Map<String, ImportFileReport> updated = {};
    try {
      final int discovered = retryable.length;
      int processed = 0;
      bool cancelled = false;

      for (final ImportFileReport file in retryable) {
        if (cancellation.isCancelled) {
          cancelled = true;
          break;
        }
        final PdfCandidate candidate = file.candidate!;
        onProgress?.call(
          ImportProgress(
            phase: ImportPhase.importing,
            processed: processed,
            discovered: discovered,
            currentFileName: candidate.fileName,
          ),
        );
        final _FileOutcome outcome = await _processCandidate(
          candidate,
          batchId: batch.id,
          cancellation: cancellation,
          operationId: _operationId(batch, processed, retry: true),
        );
        if (outcome.cancelled) {
          cancelled = true;
          break;
        }
        updated[candidate.absolutePath] = outcome.report!;
        processed++;
      }

      // Merge: replace retried files with their new result, preserve order.
      final List<ImportFileReport> merged = previous.files
          .map((f) => updated[f.path] ?? f)
          .toList();

      onProgress?.call(
        ImportProgress(
          phase: ImportPhase.finalizing,
          processed: processed,
          discovered: discovered,
        ),
      );
      return await _finalize(
        batch,
        merged,
        cancelled: cancelled,
        discovered: merged.length,
      );
    } catch (_) {
      // Preserve any results already re-produced this retry, merged over the
      // previous report, so a late failure never discards earlier successes.
      await _failBatchSafely(batch.id);
      final List<ImportFileReport> merged = previous.files
          .map((f) => updated[f.path] ?? f)
          .toList();
      return ImportRunReport(
        status: ImportBatchStatus.failed,
        files: merged,
        batch: batch,
        discoveredTotal: merged.length,
      );
    }
  }

  // --- internals ---

  Future<_FileOutcome> _processCandidate(
    PdfCandidate candidate, {
    required int batchId,
    required HashCancellation cancellation,
    required String operationId,
  }) async {
    if (_isWordSource(candidate.extension)) {
      return _processWordCandidate(
        candidate,
        batchId: batchId,
        cancellation: cancellation,
        operationId: operationId,
      );
    }

    // Bind to locals so the isolate closure captures only the (sendable) const
    // inspector and path string — never `this` (which holds the database).
    final PdfHealthInspector inspectorService = inspector;
    final String path = candidate.absolutePath;
    PdfHealthResult health;
    try {
      health = await runner<PdfHealthResult>(
        () => inspectorService.inspect(path),
      );
    } catch (_) {
      // Unexpected inspector exception: persist a failed record when possible.
      return await _serviceException(
        candidate,
        operationId,
        batchId,
        outcome: ImportFileOutcome.unreadable,
        errorCode: 'inspect_failed',
        safeMessage: 'PDF inspection failed unexpectedly',
        errorCodeEnum: ImportErrorCode.unreadable,
      );
    }

    // Missing/unreadable on disk: retain a safe failed record, never grouped.
    if (health.status == PdfHealthStatus.missing ||
        health.status == PdfHealthStatus.unreadable) {
      try {
        final result = await repository.persistFailedFile(
          FailedSourceFile(
            canonicalPath: candidate.absolutePath,
            displayName: candidate.fileName,
            extension: candidate.extension,
            sizeBytes: health.sizeBytes ?? 0,
            health: PdfHealthStatus.unreadable,
            mimeType: _pdfMimeType,
            errorCode: 'unreadable',
            safeMessage: 'file is missing or could not be read',
          ),
          outcome: ImportFileOutcome.unreadable,
          operationId: operationId,
          now: clock.nowUtc(),
          batchId: batchId,
        );
        // The repository may return alreadyImported for a previously completed
        // same-path file; always derive the final status from the actual result.
        final ImportFileStatus reportStatus = ImportFileStatus.fromOutcome(
          result.outcome,
        );
        return _FileOutcome(
          _reportFor(
            candidate,
            reportStatus,
            result,
            error: reportStatus.isFailure
                ? const ImportError(
                    code: ImportErrorCode.unreadable,
                    message: 'file is missing or could not be read',
                  )
                : null,
          ),
        );
      } catch (_) {
        return await _persistenceFailure(candidate, operationId);
      }
    }

    // Structurally corrupted: retain a safe failed record, never hash or group.
    // PdfHealthStatus.corrupted is preserved exactly — not coerced to unreadable.
    if (health.status == PdfHealthStatus.corrupted) {
      try {
        final result = await repository.persistFailedFile(
          FailedSourceFile(
            canonicalPath: candidate.absolutePath,
            displayName: candidate.fileName,
            extension: candidate.extension,
            sizeBytes: health.sizeBytes ?? 0,
            health: PdfHealthStatus.corrupted,
            mimeType: _pdfMimeType,
            errorCode: 'corrupted',
            safeMessage: 'PDF is corrupted or has no valid header',
          ),
          outcome: ImportFileOutcome.corrupted,
          operationId: operationId,
          now: clock.nowUtc(),
          batchId: batchId,
        );
        // Repository may return alreadyImported for a previously-completed path.
        final ImportFileStatus reportStatus = ImportFileStatus.fromOutcome(
          result.outcome,
        );
        return _FileOutcome(
          _reportFor(
            candidate,
            reportStatus,
            result,
            error: reportStatus.isFailure
                ? const ImportError(
                    code: ImportErrorCode.corrupted,
                    message: 'PDF is corrupted or has no valid header',
                  )
                : null,
          ),
        );
      } catch (_) {
        return await _persistenceFailure(candidate, operationId);
      }
    }

    Sha256Result hash;
    try {
      hash = await hasher.hashFile(
        candidate.absolutePath,
        cancellation: cancellation,
      );
    } catch (_) {
      // Unexpected hasher exception: persist a failed record when possible.
      return await _serviceException(
        candidate,
        operationId,
        batchId,
        outcome: ImportFileOutcome.hashFailed,
        errorCode: 'hash_failed',
        safeMessage: 'file hashing failed unexpectedly',
        errorCodeEnum: ImportErrorCode.hashFailed,
      );
    }

    if (!hash.isSuccess) {
      final ImportError error = hash.error!;
      if (error.code == ImportErrorCode.hashCancelled) {
        return const _FileOutcome.cancelled();
      }
      final bool unreadable = error.code == ImportErrorCode.unreadable;
      final ImportFileOutcome outcome = unreadable
          ? ImportFileOutcome.unreadable
          : ImportFileOutcome.hashFailed;
      try {
        final result = await repository.persistFailedFile(
          FailedSourceFile(
            canonicalPath: candidate.absolutePath,
            displayName: candidate.fileName,
            extension: candidate.extension,
            sizeBytes: candidate.sizeBytes,
            health: PdfHealthStatus.unreadable,
            mimeType: _pdfMimeType,
            errorCode: unreadable ? 'unreadable' : 'hash_failed',
            safeMessage: error.message,
          ),
          outcome: outcome,
          operationId: operationId,
          now: clock.nowUtc(),
          batchId: batchId,
        );
        // Always derive the final status from the actual repository result —
        // the repository may return alreadyImported for a previously completed
        // same-path file regardless of the requested outcome.
        final ImportFileStatus reportStatus = ImportFileStatus.fromOutcome(
          result.outcome,
        );
        return _FileOutcome(
          _reportFor(
            candidate,
            reportStatus,
            result,
            error: reportStatus.isFailure
                ? ImportError(code: error.code, message: error.message)
                : null,
          ),
        );
      } catch (_) {
        return await _persistenceFailure(candidate, operationId);
      }
    }

    // Success: healthy/unknown proceed to hash and persist.
    try {
      final result = await repository.persistHashedFile(
        PreparedSourceFile(
          canonicalPath: candidate.absolutePath,
          displayName: candidate.fileName,
          extension: candidate.extension,
          sizeBytes: health.sizeBytes ?? candidate.sizeBytes,
          sha256: hash.hash!,
          health: health.status,
          mimeType: _pdfMimeType,
          pageCount: health.pageCount,
        ),
        operationId: operationId,
        now: clock.nowUtc(),
        batchId: batchId,
      );
      return _FileOutcome(
        _reportFor(
          candidate,
          ImportFileStatus.fromOutcome(result.outcome),
          result,
          error: result.error,
        ),
      );
    } catch (_) {
      // Persistence failed after a successful hash: record a safe event and
      // continue. No schema/result key exists for this, so it is an
      // application-only status.
      return await _persistenceFailure(candidate, operationId);
    }
  }

  Future<_FileOutcome> _processWordCandidate(
    PdfCandidate candidate, {
    required int batchId,
    required HashCancellation cancellation,
    required String operationId,
  }) async {
    Sha256Result hash;
    try {
      hash = await hasher.hashFile(
        candidate.absolutePath,
        cancellation: cancellation,
      );
    } catch (_) {
      return await _serviceException(
        candidate,
        operationId,
        batchId,
        outcome: ImportFileOutcome.hashFailed,
        errorCode: 'hash_failed',
        safeMessage: 'file hashing failed unexpectedly',
        errorCodeEnum: ImportErrorCode.hashFailed,
      );
    }

    if (!hash.isSuccess) {
      final ImportError error = hash.error!;
      if (error.code == ImportErrorCode.hashCancelled) {
        return const _FileOutcome.cancelled();
      }
      final bool unreadable = error.code == ImportErrorCode.unreadable;
      final ImportFileOutcome outcome = unreadable
          ? ImportFileOutcome.unreadable
          : ImportFileOutcome.hashFailed;
      try {
        final result = await repository.persistFailedFile(
          FailedSourceFile(
            canonicalPath: candidate.absolutePath,
            displayName: candidate.fileName,
            extension: candidate.extension,
            sizeBytes: candidate.sizeBytes,
            health: PdfHealthStatus.unreadable,
            mimeType: _mimeTypeFor(candidate.extension),
            errorCode: unreadable ? 'unreadable' : 'hash_failed',
            safeMessage: error.message,
          ),
          outcome: outcome,
          operationId: operationId,
          now: clock.nowUtc(),
          batchId: batchId,
        );
        final ImportFileStatus reportStatus = ImportFileStatus.fromOutcome(
          result.outcome,
        );
        return _FileOutcome(
          _reportFor(
            candidate,
            reportStatus,
            result,
            error: reportStatus.isFailure
                ? ImportError(code: error.code, message: error.message)
                : null,
          ),
        );
      } catch (_) {
        return await _persistenceFailure(candidate, operationId);
      }
    }

    try {
      final result = await repository.persistHashedFile(
        PreparedSourceFile(
          canonicalPath: candidate.absolutePath,
          displayName: candidate.fileName,
          extension: candidate.extension,
          sizeBytes: candidate.sizeBytes,
          sha256: hash.hash!,
          health: PdfHealthStatus.healthy,
          mimeType: _mimeTypeFor(candidate.extension),
        ),
        operationId: operationId,
        now: clock.nowUtc(),
        batchId: batchId,
      );

      return _FileOutcome(
        _reportFor(
          candidate,
          ImportFileStatus.fromOutcome(result.outcome),
          result,
          error: result.error,
        ),
      );
    } catch (_) {
      return await _persistenceFailure(candidate, operationId);
    }
  }

  /// Records a safe scan-failure event for a file-less directory-enumeration
  /// failure. If even recording the event fails, the entry degrades to an
  /// application-only persistenceFailed report (and the secondary logging
  /// failure is swallowed) so later entries are never aborted.
  Future<ImportFileReport> _recordScanFailure(
    PdfScanFailure failure,
    ImportBatchRef batch,
    int processed,
  ) async {
    final String operationId = _operationId(batch, processed);
    try {
      await repository.recordFilelessOutcome(
        outcome: ImportFileOutcome.scanFailed,
        sourcePath: failure.path,
        operationId: operationId,
        now: clock.nowUtc(),
        errorCode: 'scan_failed',
        safeMessage: failure.message,
      );
      return ImportFileReport(
        fileName: _baseName(failure.path),
        path: failure.path,
        status: ImportFileStatus.scanFailed,
        error: ImportError(
          code: ImportErrorCode.scanFailed,
          path: failure.path,
          message: failure.message,
        ),
      );
    } catch (_) {
      await _recordPersistenceFailureSafely(operationId, failure.path);
      return ImportFileReport(
        fileName: _baseName(failure.path),
        path: failure.path,
        status: ImportFileStatus.persistenceFailed,
        error: ImportError(
          code: ImportErrorCode.persistenceFailed,
          path: failure.path,
          message: 'could not save the import record',
        ),
      );
    }
  }

  /// Builds a persistenceFailed outcome for a candidate whose database write
  /// threw, after recording a safe secondary event (which is itself allowed to
  /// fail safely). Earlier successful reports and later files are unaffected.
  Future<_FileOutcome> _persistenceFailure(
    PdfCandidate candidate,
    String operationId,
  ) async {
    await _recordPersistenceFailureSafely(operationId, candidate.absolutePath);
    return _FileOutcome(
      ImportFileReport(
        fileName: candidate.fileName,
        path: candidate.absolutePath,
        status: ImportFileStatus.persistenceFailed,
        candidate: candidate,
        error: ImportError(
          code: ImportErrorCode.persistenceFailed,
          path: candidate.absolutePath,
          message: 'could not save the import record',
        ),
      ),
    );
  }

  /// Best-effort safe audit of a persistence failure. A failure while logging a
  /// failure is swallowed: it must never abort the run or discard prior reports.
  Future<void> _recordPersistenceFailureSafely(
    String operationId,
    String path,
  ) async {
    try {
      await repository.recordFilelessOutcome(
        outcome: ImportFileOutcome.hashFailed,
        sourcePath: path,
        operationId: operationId,
        now: clock.nowUtc(),
        errorCode: 'persistence_failed',
        safeMessage: 'could not save the import record',
      );
    } catch (_) {
      // Intentionally swallowed.
    }
  }

  /// Handles an unexpected exception from a per-file service (inspector or
  /// hasher). Tries to retain a physical source reference via [persistFailedFile];
  /// falls back to [_persistenceFailure] (fileless event) if that also fails.
  /// Never exposes exception text or stack traces.
  Future<_FileOutcome> _serviceException(
    PdfCandidate candidate,
    String operationId,
    int batchId, {
    required ImportFileOutcome outcome,
    required String errorCode,
    required String safeMessage,
    required ImportErrorCode errorCodeEnum,
  }) async {
    try {
      final result = await repository.persistFailedFile(
        FailedSourceFile(
          canonicalPath: candidate.absolutePath,
          displayName: candidate.fileName,
          extension: candidate.extension,
          sizeBytes: candidate.sizeBytes,
          health: PdfHealthStatus.unreadable,
          mimeType: _mimeTypeFor(candidate.extension),
          errorCode: errorCode,
          safeMessage: safeMessage,
        ),
        outcome: outcome,
        operationId: operationId,
        now: clock.nowUtc(),
        batchId: batchId,
      );
      final ImportFileStatus reportStatus = ImportFileStatus.fromOutcome(
        result.outcome,
      );
      return _FileOutcome(
        _reportFor(
          candidate,
          reportStatus,
          result,
          error: reportStatus.isFailure
              ? ImportError(code: errorCodeEnum, message: safeMessage)
              : null,
        ),
      );
    } catch (_) {
      return await _persistenceFailure(candidate, operationId);
    }
  }

  /// Best-effort batch-failure marker. If [repository.failBatch] throws the
  /// secondary failure is swallowed so the coordinator can still return a safe
  /// failed [ImportRunReport] with the reports already produced.
  Future<void> _failBatchSafely(int batchId) async {
    try {
      await repository.failBatch(batchId, now: clock.nowUtc());
    } catch (_) {
      // Intentionally swallowed.
    }
  }

  ImportFileReport _reportFor(
    PdfCandidate candidate,
    ImportFileStatus status,
    ImportFileResult result, {
    ImportError? error,
  }) {
    return ImportFileReport(
      fileName: candidate.fileName,
      path: candidate.absolutePath,
      status: status,
      error: error,
      candidate: candidate,
      documentId: result.documentId,
      fileId: result.fileId,
    );
  }

  Future<ImportRunReport> _finalize(
    ImportBatchRef batch,
    List<ImportFileReport> files, {
    required bool cancelled,
    required int discovered,
  }) async {
    final ImportRunReport report = ImportRunReport(
      status: cancelled
          ? ImportBatchStatus.cancelled
          : ImportBatchStatus.completed,
      files: files,
      batch: batch,
      discoveredTotal: discovered,
    );
    final DateTime now = clock.nowUtc();
    if (cancelled) {
      // Retain the full scanned total as discovered_count even though only a
      // subset was processed before cancellation.
      await repository.updateBatchProgress(
        batch.id,
        discoveredCount: discovered,
        importedCount: report.importedCount,
        duplicateCount: report.duplicateCount,
        failedCount: report.failedCount,
        pairedCount: report.pairedWordSourceCount,
      );
      await repository.cancelBatch(batch.id, now: now);
    } else {
      await repository.completeBatch(
        batch.id,
        discoveredCount: discovered,
        importedCount: report.importedCount,
        duplicateCount: report.duplicateCount,
        failedCount: report.failedCount,
        pairedCount: report.pairedWordSourceCount,
        now: now,
      );
    }
    return report;
  }

  String _operationId(ImportBatchRef batch, int index, {bool retry = false}) =>
      '${batch.batchCode}-${retry ? 'retry-' : ''}$index';

  String _baseName(String path) {
    final int slash = path.lastIndexOf(RegExp(r'[\\/]'));
    return slash < 0 ? path : path.substring(slash + 1);
  }

  bool _isWordSource(String extension) => extension.toLowerCase() == '.doc';

  String _mimeTypeFor(String extension) {
    return extension.toLowerCase() == '.doc' ? _docMimeType : _pdfMimeType;
  }

  /// Processes a `.doc` that has been paired with an already-imported `.pdf`.
  /// Hashes the source (for audit), attaches it to [existingDocumentId], and
  /// skips the word-conversion launcher entirely.
  Future<_FileOutcome> _processPairedWordCandidate(
    PdfCandidate candidate, {
    required int existingDocumentId,
    required int batchId,
    required HashCancellation cancellation,
    required String operationId,
  }) async {
    Sha256Result hash;
    try {
      hash = await hasher.hashFile(
        candidate.absolutePath,
        cancellation: cancellation,
      );
    } catch (_) {
      return await _serviceException(
        candidate,
        operationId,
        batchId,
        outcome: ImportFileOutcome.hashFailed,
        errorCode: 'hash_failed',
        safeMessage: 'file hashing failed unexpectedly',
        errorCodeEnum: ImportErrorCode.hashFailed,
      );
    }

    if (!hash.isSuccess) {
      final ImportError error = hash.error!;
      if (error.code == ImportErrorCode.hashCancelled) {
        return const _FileOutcome.cancelled();
      }
      final bool unreadable = error.code == ImportErrorCode.unreadable;
      final ImportFileOutcome outcome = unreadable
          ? ImportFileOutcome.unreadable
          : ImportFileOutcome.hashFailed;
      try {
        final result = await repository.persistFailedFile(
          FailedSourceFile(
            canonicalPath: candidate.absolutePath,
            displayName: candidate.fileName,
            extension: candidate.extension,
            sizeBytes: candidate.sizeBytes,
            health: PdfHealthStatus.unreadable,
            mimeType: _mimeTypeFor(candidate.extension),
            errorCode: unreadable ? 'unreadable' : 'hash_failed',
            safeMessage: error.message,
          ),
          outcome: outcome,
          operationId: operationId,
          now: clock.nowUtc(),
          batchId: batchId,
        );
        final ImportFileStatus reportStatus = ImportFileStatus.fromOutcome(
          result.outcome,
        );
        return _FileOutcome(
          _reportFor(
            candidate,
            reportStatus,
            result,
            error: reportStatus.isFailure
                ? ImportError(code: error.code, message: error.message)
                : null,
          ),
        );
      } catch (_) {
        return await _persistenceFailure(candidate, operationId);
      }
    }

    try {
      final result = await repository.persistPairedWordSource(
        PreparedSourceFile(
          canonicalPath: candidate.absolutePath,
          displayName: candidate.fileName,
          extension: candidate.extension,
          sizeBytes: candidate.sizeBytes,
          sha256: hash.hash!,
          health: PdfHealthStatus.healthy,
          mimeType: _mimeTypeFor(candidate.extension),
        ),
        existingDocumentId: existingDocumentId,
        operationId: operationId,
        now: clock.nowUtc(),
        batchId: batchId,
      );
      return _FileOutcome(
        _reportFor(
          candidate,
          ImportFileStatus.fromOutcome(result.outcome),
          result,
          error: result.error,
        ),
      );
    } catch (_) {
      return await _persistenceFailure(candidate, operationId);
    }
  }

  /// Returns the set of pair keys for which both a `.pdf` and a `.doc`
  /// candidate exist (same folder, same normalized basename).
  static Set<String> _detectPairedKeys(List<PdfCandidate> candidates) {
    final Map<String, Set<String>> byKey = {};
    for (final c in candidates) {
      (byKey[_pairKey(c)] ??= {}).add(c.extension.toLowerCase());
    }
    return {
      for (final e in byKey.entries)
        if (e.value.contains('.pdf') && e.value.contains('.doc')) e.key,
    };
  }

  /// Pair key: normalized directory (including trailing separator) + TAB +
  /// normalized basename (filename without extension). Case-insensitive.
  static String _pairKey(PdfCandidate c) {
    final String path = c.absolutePath.toLowerCase();
    final String name = c.fileName.toLowerCase();
    final int dirLen = path.length - name.length;
    final String dir = dirLen > 0 ? path.substring(0, dirLen) : '';
    final String ext = c.extension.toLowerCase();
    final String base = name.substring(0, name.length - ext.length);
    return '$dir\t$base';
  }

  /// Re-orders [candidates] so that paired `.doc` files come after all other
  /// candidates (ensuring their paired PDF is imported first). Relative order
  /// within each group is preserved.
  static List<PdfCandidate> _orderWithPairedDocsLast(
    List<PdfCandidate> candidates,
    Set<String> pairedKeys,
  ) {
    if (pairedKeys.isEmpty) return candidates;
    final List<PdfCandidate> before = [];
    final List<PdfCandidate> pairedDocs = [];
    for (final c in candidates) {
      if (c.extension.toLowerCase() == '.doc' &&
          pairedKeys.contains(_pairKey(c))) {
        pairedDocs.add(c);
      } else {
        before.add(c);
      }
    }
    return [...before, ...pairedDocs];
  }
}

/// Internal result of processing one candidate: either a report or a
/// cancellation signal.
class _FileOutcome {
  const _FileOutcome(this.report) : cancelled = false;
  const _FileOutcome.cancelled() : report = null, cancelled = true;

  final ImportFileReport? report;
  final bool cancelled;
}
