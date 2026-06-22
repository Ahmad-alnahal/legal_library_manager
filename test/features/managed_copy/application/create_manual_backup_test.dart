// test/features/managed_copy/application/create_manual_backup_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/features/managed_copy/application/create_manual_backup.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/copy_roots.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/document_copy_state.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/managed_copy_persistence_data.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/managed_file_ref.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/manual_backup_result.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/source_file_candidate.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/startup_recovery_report.dart';
import 'package:legal_library_manager/features/managed_copy/domain/repositories/managed_copy_repository.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/database_backup_service.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/managed_library_filesystem.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/operation_id_generator.dart';

// ── Test doubles ──────────────────────────────────────────────────────────────

class _FakeRepository implements ManagedCopyRepository {
  String? managedRoot;
  String? backupRoot;
  final List<Map<String, Object?>> appendedEvents = [];

  _FakeRepository({this.managedRoot, this.backupRoot});

  @override
  Future<CopyRoots> loadCopyRoots() async =>
      CopyRoots(managedLibraryRoot: managedRoot, backupRoot: backupRoot);

  @override
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
  }) async {
    appendedEvents.add({
      'eventTypeKey': eventTypeKey,
      'operationId': operationId,
      'resultKey': resultKey,
      'documentId': documentId,
      'fileId': fileId,
      'destinationPath': destinationPath,
    });
  }

  // Unused in manual-backup tests; keep lean stubs only.
  @override
  Future<DocumentCopyState?> loadDocumentState(int documentId) async => null;
  @override
  Future<void> saveCopyRoots({
    required String managedLibraryRoot,
    required String backupRoot,
  }) async {}
  @override
  Future<String> loadDatabaseRoot() async => r'C:\AppData';
  @override
  Future<List<String>> loadDocumentSourcePaths(int documentId) async =>
      const [];
  @override
  Future<List<String>> loadAllSourcePaths() async => const [];
  @override
  Future<List<String>> loadManagedDocumentCodes() async => const [];
  @override
  Future<void> saveStartupRecoveryReport(StartupRecoveryReport report) async {}
  @override
  Future<StartupRecoveryReport> loadStartupRecoveryReport() async =>
      StartupRecoveryReport.healthy;
  @override
  Future<List<SourceFileCandidate>> loadEligibleSources(int documentId) async =>
      const [];
  @override
  Future<String> allocateDocumentCode(int documentId) async => 'DOC-0000001';
  @override
  Future<int> persistManagedCopySuccess(
    ManagedCopyPersistenceData data,
  ) async => 0;
  @override
  Future<List<ManagedFileRef>> loadManagedCopyFiles(int documentId) async =>
      const [];
  @override
  Future<void> markManagedFileMissing({
    required int fileId,
    required int documentId,
    required String operationId,
    required DateTime now,
  }) async {}
  @override
  Future<void> restoreManagedFileHealthy({
    required int fileId,
    required int documentId,
    required String operationId,
    required DateTime now,
  }) async {}
  @override
  Future<void> downgradeDocumentToClassified({
    required int documentId,
    required DateTime now,
  }) async {}
}

class _FakeBackupService implements DatabaseBackupService {
  final BackupResult result;
  int callCount = 0;

  _FakeBackupService(this.result);

  @override
  Future<BackupResult> createBackup({
    required String backupRoot,
    required String operationId,
    required DateTime timestamp,
  }) async {
    callCount++;
    return result;
  }
}

class _FakeFilesystem implements ManagedLibraryFilesystem {
  final bool directoryExists;

  _FakeFilesystem({required this.directoryExists});

  @override
  bool isExistingDirectory(String path) => directoryExists;

  @override
  bool isExistingFile(String path) => false;

  @override
  Future<FilesystemOperationResult> ensureDirectoryExists(
    String absoluteDirPath,
  ) async => const FilesystemSuccess();

  @override
  Future<FilesystemOperationResult> copyFile(
    String sourcePath,
    String destPath,
  ) async => const FilesystemSuccess();

  @override
  Future<FilesystemOperationResult> finalizeFile(
    String tmpPath,
    String finalPath,
  ) async => const FilesystemSuccess();

  @override
  Future<int?> fileSize(String path) async => null;

  @override
  Future<List<String>?> findRecoveryArtifacts(
    String managedFilesDir,
    String documentCode,
  ) async => const [];

  @override
  Future<List<String>?> findStartupRecoveryArtifacts(
    String managedFilesDir,
    List<String> documentCodes,
  ) async => const [];

  @override
  Future<List<String>?> findStartupBackupArtifacts(String backupRoot) async =>
      const [];

  @override
  Future<FilesystemOperationResult> deleteFile(String path) async =>
      const FilesystemSuccess();

  @override
  Future<FilesystemOperationResult> deleteRecoveryArtifact(
    String path,
    String allowedRoot,
  ) async => throw UnimplementedError();
}

class _FakeOperationIdGenerator implements OperationIdGenerator {
  @override
  String generate(DateTime timestamp) => 'op-manual-backup-test';
}

class _FixedClock extends Clock {
  @override
  DateTime nowUtc() => DateTime.utc(2026, 6, 21, 12, 0, 0);
}

// ── Helpers ───────────────────────────────────────────────────────────────────

CreateManualBackup _makeUseCase({
  required _FakeRepository repository,
  required _FakeBackupService backupService,
  bool directoryExists = true,
}) {
  return CreateManualBackup(
    repository: repository,
    backupService: backupService,
    filesystem: _FakeFilesystem(directoryExists: directoryExists),
    operationIdGenerator: _FakeOperationIdGenerator(),
    clock: _FixedClock(),
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('CreateManualBackup — precondition guards', () {
    test('returns not_configured when backup root is null', () async {
      final repo = _FakeRepository(managedRoot: r'C:\lib', backupRoot: null);
      final svc = _FakeBackupService(
        const BackupSuccess(backupPath: r'C:\b\x.sqlite'),
      );
      final result = await _makeUseCase(repository: repo, backupService: svc)();

      expect(result, isA<ManualBackupFailure>());
      expect((result as ManualBackupFailure).messageKey, 'not_configured');
      expect(
        svc.callCount,
        0,
        reason: 'backup service must not be called when root is not set',
      );
      expect(
        repo.appendedEvents,
        isEmpty,
        reason: 'no event should be appended for a pre-check failure',
      );
    });

    test('returns not_configured when backup root is empty string', () async {
      final repo = _FakeRepository(managedRoot: r'C:\lib', backupRoot: '');
      final svc = _FakeBackupService(
        const BackupSuccess(backupPath: r'C:\b\x.sqlite'),
      );
      final result = await _makeUseCase(repository: repo, backupService: svc)();

      expect(result, isA<ManualBackupFailure>());
      expect((result as ManualBackupFailure).messageKey, 'not_configured');
      expect(svc.callCount, 0);
    });

    test('returns root_missing when backup directory does not exist', () async {
      final repo = _FakeRepository(
        managedRoot: r'C:\lib',
        backupRoot: r'C:\Backups',
      );
      final svc = _FakeBackupService(
        const BackupSuccess(backupPath: r'C:\Backups\x.sqlite'),
      );
      final result = await _makeUseCase(
        repository: repo,
        backupService: svc,
        directoryExists: false,
      )();

      expect(result, isA<ManualBackupFailure>());
      expect((result as ManualBackupFailure).messageKey, 'root_missing');
      expect(
        svc.callCount,
        0,
        reason: 'backup service must not be called when directory is missing',
      );
    });
  });

  group('CreateManualBackup — successful backup', () {
    test('returns ManualBackupSuccess with the backup path', () async {
      final repo = _FakeRepository(
        managedRoot: r'C:\lib',
        backupRoot: r'C:\Backups',
      );
      const expectedPath =
          r'C:\Backups\legal_library_backup_2026-06-21_120000_op-manual-backup-test.sqlite';
      final svc = _FakeBackupService(
        const BackupSuccess(backupPath: expectedPath),
      );
      final result = await _makeUseCase(repository: repo, backupService: svc)();

      expect(result, isA<ManualBackupSuccess>());
      expect((result as ManualBackupSuccess).backupPath, expectedPath);
      expect(svc.callCount, 1);
    });

    test('appends a backup_created/succeeded file event on success', () async {
      final repo = _FakeRepository(
        managedRoot: r'C:\lib',
        backupRoot: r'C:\Backups',
      );
      const backupPath =
          r'C:\Backups\legal_library_backup_2026-06-21_120000_op-manual-backup-test.sqlite';
      final svc = _FakeBackupService(
        const BackupSuccess(backupPath: backupPath),
      );
      await _makeUseCase(repository: repo, backupService: svc)();

      expect(repo.appendedEvents, hasLength(1));
      final event = repo.appendedEvents.first;
      expect(event['eventTypeKey'], 'backup_created');
      expect(event['resultKey'], 'succeeded');
      expect(event['destinationPath'], backupPath);
      expect(
        event['documentId'],
        isNull,
        reason: 'backup events must not reference any document',
      );
      expect(
        event['fileId'],
        isNull,
        reason: 'backup events must not reference any file',
      );
    });

    test('event operationId is non-empty', () async {
      final repo = _FakeRepository(
        managedRoot: r'C:\lib',
        backupRoot: r'C:\Backups',
      );
      const backupPath = r'C:\Backups\backup.sqlite';
      final svc = _FakeBackupService(
        const BackupSuccess(backupPath: backupPath),
      );
      await _makeUseCase(repository: repo, backupService: svc)();

      expect(repo.appendedEvents.first['operationId'], isNotEmpty);
    });
  });

  group('CreateManualBackup — backup service failure', () {
    test('returns failed when backup service returns BackupFailure', () async {
      final repo = _FakeRepository(
        managedRoot: r'C:\lib',
        backupRoot: r'C:\Backups',
      );
      final svc = _FakeBackupService(
        const BackupFailure(safeMessage: 'Backup creation failed.'),
      );
      final result = await _makeUseCase(repository: repo, backupService: svc)();

      expect(result, isA<ManualBackupFailure>());
      expect((result as ManualBackupFailure).messageKey, 'failed');
    });

    test('appends a backup_created/failed event on service failure', () async {
      final repo = _FakeRepository(
        managedRoot: r'C:\lib',
        backupRoot: r'C:\Backups',
      );
      final svc = _FakeBackupService(
        const BackupFailure(safeMessage: 'Backup verification failed.'),
      );
      await _makeUseCase(repository: repo, backupService: svc)();

      expect(repo.appendedEvents, hasLength(1));
      expect(repo.appendedEvents.first['eventTypeKey'], 'backup_created');
      expect(repo.appendedEvents.first['resultKey'], 'failed');
      expect(repo.appendedEvents.first['destinationPath'], isNull);
    });

    test(
      'returns failed when backup file already exists (no overwrite)',
      () async {
        final repo = _FakeRepository(
          managedRoot: r'C:\lib',
          backupRoot: r'C:\Backups',
        );
        final svc = _FakeBackupService(
          const BackupFailure(
            safeMessage: 'Backup file already exists: x.sqlite',
          ),
        );
        final result = await _makeUseCase(
          repository: repo,
          backupService: svc,
        )();

        expect(result, isA<ManualBackupFailure>());
        expect((result as ManualBackupFailure).messageKey, 'failed');
      },
    );
  });

  group('CreateManualBackup — source file safety invariants', () {
    test('never passes a source path to the backup service', () async {
      // The backup service only receives backupRoot, operationId, timestamp.
      // There is no source-file path parameter on DatabaseBackupService.createBackup.
      // This is a compile-time guarantee, but we document it here.
      //
      // Confirm the service is called with the configured backup root only.
      final repo = _FakeRepository(
        managedRoot: r'C:\OriginalSources',
        backupRoot: r'C:\Backups',
      );
      String? capturedRoot;
      final svc = _CapturingBackupService(
        onCall: (root, _, _) => capturedRoot = root,
        result: const BackupSuccess(backupPath: r'C:\Backups\x.sqlite'),
      );
      await CreateManualBackup(
        repository: repo,
        backupService: svc,
        filesystem: _FakeFilesystem(directoryExists: true),
        operationIdGenerator: _FakeOperationIdGenerator(),
        clock: _FixedClock(),
      )();

      expect(capturedRoot, r'C:\Backups');
      expect(
        capturedRoot,
        isNot(contains('OriginalSources')),
        reason: 'backup root must never be the source-file root',
      );
    });
  });
}

/// Captures the arguments passed to createBackup.
class _CapturingBackupService implements DatabaseBackupService {
  _CapturingBackupService({required this.onCall, required this.result});

  final void Function(String root, String opId, DateTime ts) onCall;
  final BackupResult result;

  @override
  Future<BackupResult> createBackup({
    required String backupRoot,
    required String operationId,
    required DateTime timestamp,
  }) async {
    onCall(backupRoot, operationId, timestamp);
    return result;
  }
}
