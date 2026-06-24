// lib/features/managed_copy/application/reconcile_managed_copy_integrity.dart
// ignore_for_file: prefer_initializing_formals

import '../../../core/time/clock.dart';
import '../../import/domain/services/file_hasher.dart';
import '../../security/application/session_manager.dart';
import '../../security/application/step_up_manager.dart';
import '../../security/application/step_up_required_exception.dart';
import '../../security/application/unauthorized_exception.dart';
import '../../security/domain/entities/account_role.dart';
import '../domain/entities/managed_file_ref.dart';
import '../domain/entities/reconcile_integrity_result.dart';
import '../domain/repositories/managed_copy_repository.dart';
import '../domain/services/managed_library_filesystem.dart';
import '../domain/services/operation_id_generator.dart';

/// Checks the physical integrity of every registered managed-copy file and
/// reconciles mismatches in the database. Source files are never accessed.
///
/// For each managed-copy file record:
/// - If the file is absent from disk, it is marked missing.
/// - If the file exists but its size or SHA-256 differs from stored metadata,
///   it is marked corrupted.
/// - If a previously-missing or corrupted file is now present and its content
///   matches stored metadata, it is restored to healthy.
/// - If a document has no remaining healthy managed copy after reconciliation,
///   its workflow status is moved back to classified.
///
/// No files are created, moved, copied, or deleted by this use case.
///
/// Throws [UnauthorizedException] if the caller does not hold an active
/// administrator session.
class ReconcileManagedCopyIntegrity {
  const ReconcileManagedCopyIntegrity({
    required ManagedCopyRepository repository,
    required ManagedLibraryFilesystem filesystem,
    required FileHasher hasher,
    required OperationIdGenerator operationIdGenerator,
    required Clock clock,
    required SessionManager sessionManager,
    required StepUpManager stepUpManager,
  }) : _repository = repository,
       _filesystem = filesystem,
       _hasher = hasher,
       _operationIdGenerator = operationIdGenerator,
       _clock = clock,
       _sessionManager = sessionManager,
       _stepUpManager = stepUpManager;

  final ManagedCopyRepository _repository;
  final ManagedLibraryFilesystem _filesystem;
  final FileHasher _hasher;
  final OperationIdGenerator _operationIdGenerator;
  final Clock _clock;
  final SessionManager _sessionManager;
  final StepUpManager _stepUpManager;

  Future<ReconcileIntegrityResult> call() async {
    final session = _sessionManager.currentSession;
    if (session == null || session.role != AccountRole.admin) {
      throw const UnauthorizedException(
        'Admin role required to run the managed-copy integrity scan.',
      );
    }
    if (!_stepUpManager.isApproved) {
      throw const StepUpRequiredException();
    }

    final allFiles = await _repository.loadAllManagedCopyFiles();
    if (allFiles.isEmpty) return ReconcileIntegrityResult.empty;

    final byDocument = <int, List<ManagedFileRef>>{};
    for (final file in allFiles) {
      (byDocument[file.documentId] ??= []).add(file);
    }

    var healthy = 0;
    var missing = 0;
    var corrupted = 0;
    var restored = 0;
    var failed = 0;
    var downgraded = 0;

    for (final entry in byDocument.entries) {
      final docId = entry.key;
      final files = entry.value;
      var docHasHealthy = false;

      for (final file in files) {
        final outcome = await _checkFile(file);
        switch (outcome) {
          case _Outcome.healthy:
            healthy++;
            docHasHealthy = true;
          case _Outcome.restored:
            restored++;
            docHasHealthy = true;
          case _Outcome.markedMissing:
            missing++;
          case _Outcome.markedCorrupted:
            corrupted++;
          case _Outcome.alreadyUnhealthy:
            break;
          case _Outcome.failed:
            failed++;
        }
      }

      if (!docHasHealthy) {
        try {
          await _repository.downgradeDocumentToClassified(
            documentId: docId,
            now: _clock.nowUtc(),
          );
          downgraded++;
        } catch (_) {
          failed++;
        }
      }
    }

    return ReconcileIntegrityResult(
      healthyCount: healthy,
      missingCount: missing,
      corruptedCount: corrupted,
      restoredCount: restored,
      downgradedDocumentCount: downgraded,
      failedCount: failed,
    );
  }

  Future<_Outcome> _checkFile(ManagedFileRef file) async {
    final isCurrentlyUnhealthy =
        file.fileHealthKey == 'missing' || file.fileHealthKey == 'corrupted';

    if (!_filesystem.isExistingFile(file.absolutePath)) {
      if (file.fileHealthKey == 'missing') {
        // Already correctly recorded as missing; no DB update needed.
        return _Outcome.alreadyUnhealthy;
      }
      // Was healthy or corrupted; physical file is now absent.
      return await _doMarkMissing(file);
    }

    // File is present on disk — verify content integrity.
    final contentOk = await _isContentOk(file);

    if (contentOk == null) {
      // Filesystem or hash I/O error; leave DB unchanged.
      return _Outcome.failed;
    }

    if (!contentOk) {
      if (file.fileHealthKey == 'corrupted') {
        // Content still mismatches; no change needed.
        return _Outcome.alreadyUnhealthy;
      }
      // Newly detected mismatch (or file came back but content is wrong).
      return await _doMarkCorrupted(file);
    }

    // Content matches stored metadata.
    if (!isCurrentlyUnhealthy) {
      return _Outcome.healthy;
    }

    // File was unhealthy but is now verified healthy — restore it.
    try {
      final now = _clock.nowUtc();
      await _repository.restoreManagedFileHealthy(
        fileId: file.fileId,
        documentId: file.documentId,
        operationId: _operationIdGenerator.generate(now),
        now: now,
      );
      return _Outcome.restored;
    } catch (_) {
      return _Outcome.failed;
    }
  }

  /// Returns true if the physical file's content matches stored metadata,
  /// false on mismatch, or null when the check could not be completed.
  Future<bool?> _isContentOk(ManagedFileRef file) async {
    if (file.fileSizeBytes > 0) {
      final size = await _filesystem.fileSize(file.absolutePath);
      if (size == null) return null;
      if (size != file.fileSizeBytes) return false;
    }

    final storedHash = file.sha256Hash;
    if (storedHash == null || storedHash.isEmpty) return true;

    final hashResult = await _hasher.hashFile(file.absolutePath);
    if (!hashResult.isSuccess) return null;
    return hashResult.hash == storedHash;
  }

  Future<_Outcome> _doMarkMissing(ManagedFileRef file) async {
    try {
      final now = _clock.nowUtc();
      await _repository.markManagedFileMissing(
        fileId: file.fileId,
        documentId: file.documentId,
        operationId: _operationIdGenerator.generate(now),
        now: now,
      );
      return _Outcome.markedMissing;
    } catch (_) {
      return _Outcome.failed;
    }
  }

  Future<_Outcome> _doMarkCorrupted(ManagedFileRef file) async {
    try {
      final now = _clock.nowUtc();
      await _repository.markManagedFileCorrupted(
        fileId: file.fileId,
        documentId: file.documentId,
        operationId: _operationIdGenerator.generate(now),
        now: now,
      );
      return _Outcome.markedCorrupted;
    } catch (_) {
      return _Outcome.failed;
    }
  }
}

enum _Outcome {
  healthy,
  restored,
  markedMissing,
  markedCorrupted,
  alreadyUnhealthy,
  failed,
}
