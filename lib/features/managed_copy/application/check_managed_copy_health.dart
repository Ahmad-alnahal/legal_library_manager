// lib/features/managed_copy/application/check_managed_copy_health.dart

import '../../../core/time/clock.dart';
import '../../import/domain/services/file_hasher.dart';
import '../domain/entities/managed_file_ref.dart';
import '../domain/repositories/managed_copy_repository.dart';
import '../domain/services/managed_library_filesystem.dart';
import '../domain/services/operation_id_generator.dart';

/// Outcome of a physical-file health check on a document's managed copy.
enum CheckManagedCopyHealthResult {
  /// No managed-copy file records exist for this document.
  notApplicable,

  /// Every non-missing managed-copy file is physically present on disk.
  healthy,

  /// All managed-copy records were already marked 'missing'; no file row was
  /// changed. The document is still downgraded idempotently so stale
  /// copied_to_library states are repaired.
  alreadyMissing,

  /// At least one non-missing managed-copy file was physically absent. The
  /// repository was updated and, when no healthy managed copy remains, the
  /// document is downgraded from copied_to_library to classified so re-copy is
  /// possible.
  missingReconciled,

  /// A reconciliation update was attempted but failed.
  reconciliationFailed,
}

/// Checks whether a document's managed-copy file records are physically present
/// on disk and reconciles any discrepancy.
///
/// Missing physical files are marked missing in the database. If no healthy
/// managed copy remains afterward, the document is made copyable again by
/// downgrading its workflow to classified. Old managed-copy rows are preserved.
class CheckManagedCopyHealth {
  const CheckManagedCopyHealth({
    required this._repository,
    required this._filesystem,
    required this._hasher,
    required this._operationIdGenerator,
    required this._clock,
  });

  final ManagedCopyRepository _repository;
  final ManagedLibraryFilesystem _filesystem;
  final FileHasher _hasher;
  final OperationIdGenerator _operationIdGenerator;
  final Clock _clock;

  Future<CheckManagedCopyHealthResult> call(int documentId) async {
    final managedFiles = await _repository.loadManagedCopyFiles(documentId);
    if (managedFiles.isEmpty) return CheckManagedCopyHealthResult.notApplicable;

    final nonMissing = managedFiles
        .where((file) => file.fileHealthKey != 'missing')
        .toList();

    var anyRestored = false;
    for (final missing in managedFiles.where(
      (file) => file.fileHealthKey == 'missing',
    )) {
      final restored = await _tryRestoreMissingFile(
        documentId: documentId,
        file: missing,
      );
      if (restored == _RestoredFileCheck.failed) {
        return CheckManagedCopyHealthResult.reconciliationFailed;
      }
      if (restored == _RestoredFileCheck.restored) {
        anyRestored = true;
      }
    }

    if (nonMissing.isEmpty) {
      if (anyRestored) return CheckManagedCopyHealthResult.missingReconciled;
      try {
        await _repository.downgradeDocumentToClassified(
          documentId: documentId,
          now: _clock.nowUtc(),
        );
      } catch (_) {
        return CheckManagedCopyHealthResult.reconciliationFailed;
      }
      return CheckManagedCopyHealthResult.alreadyMissing;
    }

    var anyReconciled = false;
    var anyPresent = false;

    for (final managed in nonMissing) {
      if (_filesystem.isExistingFile(managed.absolutePath)) {
        anyPresent = true;
        continue;
      }

      final now = _clock.nowUtc();
      final operationId = _operationIdGenerator.generate(now);
      try {
        await _repository.markManagedFileMissing(
          fileId: managed.fileId,
          documentId: documentId,
          operationId: operationId,
          now: now,
        );
        anyReconciled = true;
      } catch (_) {
        return CheckManagedCopyHealthResult.reconciliationFailed;
      }
    }

    if (anyReconciled && !anyPresent) {
      try {
        await _repository.downgradeDocumentToClassified(
          documentId: documentId,
          now: _clock.nowUtc(),
        );
      } catch (_) {
        return CheckManagedCopyHealthResult.reconciliationFailed;
      }
    }

    if (anyReconciled || anyRestored) {
      return CheckManagedCopyHealthResult.missingReconciled;
    }
    return CheckManagedCopyHealthResult.healthy;
  }

  Future<_RestoredFileCheck> _tryRestoreMissingFile({
    required int documentId,
    required ManagedFileRef file,
  }) async {
    if (!_filesystem.isExistingFile(file.absolutePath)) {
      return _RestoredFileCheck.notRestored;
    }

    final storedHash = file.sha256Hash;
    if (storedHash == null || storedHash.isEmpty) {
      return _RestoredFileCheck.notRestored;
    }

    final size = await _filesystem.fileSize(file.absolutePath);
    if (size == null || size != file.fileSizeBytes) {
      return _RestoredFileCheck.notRestored;
    }

    final hash = await _hasher.hashFile(file.absolutePath);
    if (!hash.isSuccess || hash.hash != storedHash) {
      return _RestoredFileCheck.notRestored;
    }

    final now = _clock.nowUtc();
    final operationId = _operationIdGenerator.generate(now);
    try {
      await _repository.restoreManagedFileHealthy(
        fileId: file.fileId,
        documentId: documentId,
        operationId: operationId,
        now: now,
      );
    } catch (_) {
      return _RestoredFileCheck.failed;
    }

    return _RestoredFileCheck.restored;
  }
}

enum _RestoredFileCheck { notRestored, restored, failed }
