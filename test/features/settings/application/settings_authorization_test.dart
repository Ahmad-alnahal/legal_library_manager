// test/features/settings/application/settings_authorization_test.dart
//
// Proves that each admin-only Settings action rejects operators even when the
// UI guard is bypassed and the use case is called directly.

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/managed_copy/application/apply_default_copy_roots.dart';
import 'package:legal_library_manager/features/managed_copy/application/configure_copy_roots.dart';
import 'package:legal_library_manager/features/managed_copy/application/create_manual_backup.dart';
import 'package:legal_library_manager/features/managed_copy/application/reconcile_managed_copy_integrity.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/copy_roots.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/managed_copy_persistence_data.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/managed_file_ref.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/manual_backup_result.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/source_file_candidate.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/startup_recovery_report.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/document_copy_state.dart';
import 'package:legal_library_manager/features/managed_copy/domain/repositories/managed_copy_repository.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/database_backup_service.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/documents_directory_resolver.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/managed_library_filesystem.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/operation_id_generator.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/path_canonicalizer.dart';
import 'package:legal_library_manager/features/import/domain/entities/import_error.dart';
import 'package:legal_library_manager/features/import/domain/entities/sha256_result.dart';
import 'package:legal_library_manager/features/import/domain/services/file_hasher.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/features/security/application/session_manager.dart';
import 'package:legal_library_manager/features/security/application/unauthorized_exception.dart';
import 'package:legal_library_manager/features/security/domain/entities/account_role.dart';
import 'package:legal_library_manager/features/security/domain/entities/session.dart';

// ── Test doubles ──────────────────────────────────────────────────────────────

class _NullRepo implements ManagedCopyRepository {
  @override
  Future<CopyRoots> loadCopyRoots() async =>
      const CopyRoots(managedLibraryRoot: r'C:\lib', backupRoot: r'C:\bk');
  @override
  Future<String> loadDatabaseRoot() async => r'C:\db';
  @override
  Future<List<String>> loadAllSourcePaths() async => const [];
  @override
  Future<void> saveCopyRoots({
    required String managedLibraryRoot,
    required String backupRoot,
  }) async {}
  @override
  Future<List<ManagedFileRef>> loadAllManagedCopyFiles() async => const [];
  @override
  Future<void> markManagedFileMissing({
    required int fileId,
    required int documentId,
    required String operationId,
    required DateTime now,
  }) async {}
  @override
  Future<void> markManagedFileCorrupted({
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
  }) async {}
  @override
  Future<DocumentCopyState?> loadDocumentState(int documentId) async => null;
  @override
  Future<List<String>> loadDocumentSourcePaths(int documentId) async =>
      const [];
  @override
  Future<List<String>> loadManagedDocumentCodes() async => const [];
  @override
  Future<StartupRecoveryReport> loadStartupRecoveryReport() async =>
      StartupRecoveryReport.healthy;
  @override
  Future<void> saveStartupRecoveryReport(StartupRecoveryReport report) async {}
  @override
  Future<List<SourceFileCandidate>> loadEligibleSources(int documentId) async =>
      const [];
  @override
  Future<String> allocateDocumentCode(int documentId) async => 'DOC-0000001';
  @override
  Future<int> persistManagedCopySuccess(ManagedCopyPersistenceData data) async =>
      0;
  @override
  Future<List<ManagedFileRef>> loadManagedCopyFiles(int documentId) async =>
      const [];
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('$i');
}

class _NullFilesystem implements ManagedLibraryFilesystem {
  @override
  bool isExistingDirectory(String path) => true;
  @override
  bool isExistingFile(String path) => false;
  @override
  Future<FilesystemOperationResult> ensureDirectoryExists(
          String absoluteDirPath) async =>
      const FilesystemSuccess();
  @override
  Future<FilesystemOperationResult> copyFile(
          String sourcePath, String destPath) async =>
      const FilesystemSuccess();
  @override
  Future<FilesystemOperationResult> finalizeFile(
          String tmpPath, String finalPath) async =>
      const FilesystemSuccess();
  @override
  Future<int?> fileSize(String path) async => null;
  @override
  Future<List<String>?> findRecoveryArtifacts(
          String managedFilesDir, String documentCode) async =>
      const [];
  @override
  Future<List<String>?> findStartupRecoveryArtifacts(
          String managedFilesDir, List<String> documentCodes) async =>
      const [];
  @override
  Future<List<String>?> findStartupBackupArtifacts(String backupRoot) async =>
      const [];
  @override
  Future<FilesystemOperationResult> deleteFile(String path) async =>
      const FilesystemSuccess();
  @override
  Future<FilesystemOperationResult> deleteRecoveryArtifact(
          String path, String allowedRoot) async =>
      const FilesystemSuccess();
}

class _NullBackupService implements DatabaseBackupService {
  @override
  Future<BackupResult> createBackup({
    required String backupRoot,
    required String operationId,
    required DateTime timestamp,
  }) async =>
      const BackupSuccess(backupPath: r'C:\bk\x.sqlite');
}

class _NullCanonicalizer implements PathCanonicalizer {
  @override
  String? canonicalize(String path) => path;
}

class _NullClock extends Clock {
  @override
  DateTime nowUtc() => DateTime.utc(2026, 6, 24, 9);
}

class _NullOpGen implements OperationIdGenerator {
  @override
  String generate(DateTime timestamp) => 'op-test';
}

class _NullDocumentsResolver implements DocumentsDirectoryResolver {
  @override
  Future<String?> resolveDocumentsPath() async => r'C:\Users\test\Documents';
}

class _NullHasher implements FileHasher {
  @override
  Future<Sha256Result> hashFile(
    String absolutePath, {
    HashCancellation? cancellation,
    void Function(HashProgress progress)? onProgress,
  }) async =>
      Sha256Result.failure(
        ImportError(code: ImportErrorCode.hashFailed, path: absolutePath, message: ''),
      );
}

// ── Operator session fixture ───────────────────────────────────────────────────

SessionManager _operatorManager() {
  final mgr = SessionManager();
  mgr.login(Session(
    accountId: 'op1',
    username: 'op@operator',
    role: AccountRole.operator,
    startedAt: DateTime.utc(2026, 6, 24, 9),
  ));
  return mgr;
}

SessionManager _noSessionManager() => SessionManager();

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('Settings authorization — operator cannot bypass UI guard', () {
    // ── ConfigureCopyRoots ─────────────────────────────────────────────────

    group('ConfigureCopyRoots', () {
      ConfigureCopyRoots make(SessionManager mgr) => ConfigureCopyRoots(
            _NullRepo(),
            _NullFilesystem(),
            _NullCanonicalizer(),
            sessionManager: mgr,
          );

      test('operator session → unauthorized', () async {
        final mgr = _operatorManager();
        expect(
          await make(mgr)(r'C:\Managed', r'D:\Backups'),
          ConfigureCopyRootsResult.unauthorized,
        );
        mgr.dispose();
      });

      test('no session → unauthorized', () async {
        final mgr = _noSessionManager();
        expect(
          await make(mgr)(r'C:\Managed', r'D:\Backups'),
          ConfigureCopyRootsResult.unauthorized,
        );
        mgr.dispose();
      });
    });

    // ── ApplyDefaultCopyRoots ──────────────────────────────────────────────

    group('ApplyDefaultCopyRoots', () {
      ApplyDefaultCopyRoots make(SessionManager mgr) {
        final configureCopyRoots = ConfigureCopyRoots(
          _NullRepo(),
          _NullFilesystem(),
          _NullCanonicalizer(),
          sessionManager: mgr,
        );
        return ApplyDefaultCopyRoots(
          documentsResolver: _NullDocumentsResolver(),
          filesystem: _NullFilesystem(),
          configureCopyRoots: configureCopyRoots,
          sessionManager: mgr,
        );
      }

      test('operator session → unauthorized', () async {
        final mgr = _operatorManager();
        expect(await make(mgr)(), ApplyDefaultCopyRootsResult.unauthorized);
        mgr.dispose();
      });

      test('no session → unauthorized', () async {
        final mgr = _noSessionManager();
        expect(await make(mgr)(), ApplyDefaultCopyRootsResult.unauthorized);
        mgr.dispose();
      });
    });

    // ── CreateManualBackup ─────────────────────────────────────────────────

    group('CreateManualBackup', () {
      CreateManualBackup make(SessionManager mgr) => CreateManualBackup(
            repository: _NullRepo(),
            backupService: _NullBackupService(),
            filesystem: _NullFilesystem(),
            operationIdGenerator: _NullOpGen(),
            clock: _NullClock(),
            sessionManager: mgr,
          );

      test('operator session → ManualBackupFailure(unauthorized)', () async {
        final mgr = _operatorManager();
        final result = await make(mgr)();
        expect(result, isA<ManualBackupFailure>());
        expect((result as ManualBackupFailure).messageKey, 'unauthorized');
        mgr.dispose();
      });

      test('no session → ManualBackupFailure(unauthorized)', () async {
        final mgr = _noSessionManager();
        final result = await make(mgr)();
        expect(result, isA<ManualBackupFailure>());
        expect((result as ManualBackupFailure).messageKey, 'unauthorized');
        mgr.dispose();
      });
    });

    // ── ReconcileManagedCopyIntegrity ──────────────────────────────────────

    group('ReconcileManagedCopyIntegrity', () {
      ReconcileManagedCopyIntegrity make(SessionManager mgr) =>
          ReconcileManagedCopyIntegrity(
            repository: _NullRepo(),
            filesystem: _NullFilesystem(),
            hasher: _NullHasher(),
            operationIdGenerator: _NullOpGen(),
            clock: _NullClock(),
            sessionManager: mgr,
          );

      test('operator session → throws UnauthorizedException', () async {
        final mgr = _operatorManager();
        await expectLater(make(mgr).call(), throwsA(isA<UnauthorizedException>()));
        mgr.dispose();
      });

      test('no session → throws UnauthorizedException', () async {
        final mgr = _noSessionManager();
        await expectLater(make(mgr).call(), throwsA(isA<UnauthorizedException>()));
        mgr.dispose();
      });
    });
  });
}
