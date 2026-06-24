// lib/features/managed_copy/application/create_manual_backup.dart

import '../../../core/time/clock.dart';
import '../../security/application/session_manager.dart';
import '../../security/domain/entities/account_role.dart';
import '../domain/entities/manual_backup_result.dart';
import '../domain/repositories/managed_copy_repository.dart';
import '../domain/services/database_backup_service.dart';
import '../domain/services/managed_library_filesystem.dart';
import '../domain/services/operation_id_generator.dart';

/// Creates a verified database-only backup into the configured backup root.
///
/// The backup covers app database records (metadata, classifications, events)
/// only. Original source files, managed PDFs, exports, logs, and temp files
/// are never included or touched. No dart:io, Drift, FFI, or Windows APIs are
/// imported here.
///
/// Throws/returns [ManualBackupFailure] with `'unauthorized'` if the current
/// session is not an active administrator session.
class CreateManualBackup {
  const CreateManualBackup({
    required this._repository,
    required this._backupService,
    required this._filesystem,
    required this._operationIdGenerator,
    required this._clock,
    required this._sessionManager,
  });

  final ManagedCopyRepository _repository;
  final DatabaseBackupService _backupService;
  final ManagedLibraryFilesystem _filesystem;
  final OperationIdGenerator _operationIdGenerator;
  final Clock _clock;
  final SessionManager _sessionManager;

  Future<ManualBackupResult> call() async {
    // ── 0. Authorization guard ────────────────────────────────────────────────
    final session = _sessionManager.currentSession;
    if (session == null || session.role != AccountRole.admin) {
      return const ManualBackupFailure(messageKey: 'unauthorized');
    }

    // ── 1. Validate backup root from settings ─────────────────────────────────

    final roots = await _repository.loadCopyRoots();
    final backupRoot = roots.backupRoot;

    if (backupRoot == null || backupRoot.trim().isEmpty) {
      return const ManualBackupFailure(messageKey: 'not_configured');
    }

    if (!_filesystem.isExistingDirectory(backupRoot)) {
      return const ManualBackupFailure(messageKey: 'root_missing');
    }

    // ── 2. Create verified backup ─────────────────────────────────────────────

    final now = _clock.nowUtc();
    final operationId = _operationIdGenerator.generate(now);

    final result = await _backupService.createBackup(
      backupRoot: backupRoot,
      operationId: operationId,
      timestamp: now,
    );

    // ── 3. Record audit event and return typed result ─────────────────────────

    switch (result) {
      case BackupSuccess(:final backupPath):
        await _appendEvent(
          operationId: operationId,
          resultKey: 'succeeded',
          destinationPath: backupPath,
        );
        return ManualBackupSuccess(backupPath: backupPath);

      case BackupFailure():
        await _appendEvent(operationId: operationId, resultKey: 'failed');
        return const ManualBackupFailure(messageKey: 'failed');
    }
  }

  Future<void> _appendEvent({
    required String operationId,
    required String resultKey,
    String? destinationPath,
  }) async {
    try {
      await _repository.appendFileEvent(
        documentId: null,
        fileId: null,
        eventTypeKey: 'backup_created',
        operationId: operationId,
        resultKey: resultKey,
        destinationPath: destinationPath,
      );
    } catch (_) {
      // Audit failure must not mask the backup result.
    }
  }
}
