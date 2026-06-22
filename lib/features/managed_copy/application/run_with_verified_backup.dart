// lib/features/managed_copy/application/run_with_verified_backup.dart
// ignore_for_file: prefer_initializing_formals

import '../../../core/time/clock.dart';
import '../domain/entities/verified_backup_guard_result.dart';
import '../domain/repositories/managed_copy_repository.dart';
import '../domain/services/database_backup_service.dart';
import '../domain/services/managed_library_filesystem.dart';
import '../domain/services/operation_id_generator.dart';

/// Reusable guard that creates a verified database backup before running any
/// risky multi-row, destructive, or bulk operation.
///
/// Safety contract:
/// - Backup root is validated (configured, directory exists) before attempting.
/// - If the backup root is not configured, the operation is never started.
/// - If the backup directory is missing, the operation is never started.
/// - If the backup service fails, the operation is never started.
/// - The operation runs only after a successful, verified backup.
/// - The operation callback takes no parameters — callers capture inputs via
///   closure, which prevents source-file paths from entering the guard API.
/// - Original source files are never touched by this class.
///
/// No dart:io, Drift, FFI, or Windows APIs are imported here.
class RunWithVerifiedBackup {
  const RunWithVerifiedBackup({
    required ManagedCopyRepository repository,
    required DatabaseBackupService backupService,
    required ManagedLibraryFilesystem filesystem,
    required OperationIdGenerator operationIdGenerator,
    required Clock clock,
  }) : _repository = repository,
       _backupService = backupService,
       _filesystem = filesystem,
       _operationIdGenerator = operationIdGenerator,
       _clock = clock;

  final ManagedCopyRepository _repository;
  final DatabaseBackupService _backupService;
  final ManagedLibraryFilesystem _filesystem;
  final OperationIdGenerator _operationIdGenerator;
  final Clock _clock;

  /// Runs [operation] only after a verified database backup succeeds.
  ///
  /// The callback intentionally accepts no parameters. Callers must capture
  /// any inputs via closure — this prevents source-file paths from being
  /// passed into the guard API.
  ///
  /// Returns a [VerifiedBackupGuardResult] that distinguishes:
  /// - [GuardBackupNotConfigured] — backup root is not set in settings.
  /// - [GuardBackupRootMissing]   — backup root configured but directory absent.
  /// - [GuardBackupFailed]        — backup service returned an error.
  /// - [GuardOperationSucceeded]  — backup and operation both succeeded.
  /// - [GuardOperationFailed]     — backup succeeded but operation threw.
  Future<VerifiedBackupGuardResult<T>> call<T>(
    Future<T> Function() operation,
  ) async {
    // ── 1. Validate backup root ───────────────────────────────────────────────

    final roots = await _repository.loadCopyRoots();
    final backupRoot = roots.backupRoot;

    if (backupRoot == null || backupRoot.trim().isEmpty) {
      return GuardBackupNotConfigured<T>();
    }

    if (!_filesystem.isExistingDirectory(backupRoot)) {
      return GuardBackupRootMissing<T>();
    }

    // ── 2. Create verified backup ─────────────────────────────────────────────

    final now = _clock.nowUtc();
    final operationId = _operationIdGenerator.generate(now);

    final backupResult = await _backupService.createBackup(
      backupRoot: backupRoot,
      operationId: operationId,
      timestamp: now,
    );

    switch (backupResult) {
      case BackupFailure():
        await _appendBackupEvent(operationId: operationId, resultKey: 'failed');
        return GuardBackupFailed<T>();

      case BackupSuccess(:final backupPath):
        await _appendBackupEvent(
          operationId: operationId,
          resultKey: 'succeeded',
          destinationPath: backupPath,
        );

        // ── 3. Run the guarded operation ──────────────────────────────────────

        try {
          final value = await operation();
          return GuardOperationSucceeded<T>(
            value: value,
            backupPath: backupPath,
          );
        } catch (e) {
          return GuardOperationFailed<T>(error: e, backupPath: backupPath);
        }
    }
  }

  Future<void> _appendBackupEvent({
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
      // Audit failure must not mask the backup or operation result.
    }
  }
}
