// test/features/managed_copy/application/cleanup_recovery_artifacts_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/managed_copy/application/cleanup_recovery_artifacts.dart';
import 'package:legal_library_manager/features/managed_copy/application/inspect_startup_recovery.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/cleanup_recovery_result.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/copy_roots.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/recovery_artifact_summary.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/startup_recovery_report.dart';
import 'package:legal_library_manager/features/managed_copy/domain/repositories/managed_copy_repository.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/managed_library_filesystem.dart';

void main() {
  const managedRoot = r'C:\MARJIY\ManagedLibrary';
  const backupRoot = r'C:\MARJIY\DatabaseBackups';

  group('CleanupRecoveryArtifacts', () {
    test('deletes eligible .copying files and returns cleaned', () async {
      const path =
          r'C:\MARJIY\ManagedLibrary\files\DOC-0000002.pdf.copy_abc.copying';
      final repo = _FakeRepo(
        roots: const CopyRoots(managedLibraryRoot: managedRoot),
      );
      final fs = _FakeFilesystem()
        ..deletionResults[path] = const FilesystemSuccess();
      final inspect = _FakeInspect(repo, fs);
      final useCase = CleanupRecoveryArtifacts(
        repository: repo,
        filesystem: fs,
        inspectStartupRecovery: inspect,
      );
      final summary = RecoveryArtifactSummary(copyingFiles: const [path]);

      final result = await useCase(summary);

      expect(result, CleanupRecoveryResult.cleaned);
      expect(fs.deletedPaths, contains(path));
      expect(inspect.callCount, 1);
    });

    test(
      'deletes eligible incomplete backup files and returns cleaned',
      () async {
        const path =
            r'C:\MARJIY\DatabaseBackups\legal_library_backup_2026-06-21_120000_manual.sqlite';
        final repo = _FakeRepo(roots: const CopyRoots(backupRoot: backupRoot));
        final fs = _FakeFilesystem()
          ..deletionResults[path] = const FilesystemSuccess();
        final inspect = _FakeInspect(repo, fs);
        final useCase = CleanupRecoveryArtifacts(
          repository: repo,
          filesystem: fs,
          inspectStartupRecovery: inspect,
        );
        final summary = RecoveryArtifactSummary(
          incompleteBackups: const [path],
        );

        final result = await useCase(summary);

        expect(result, CleanupRecoveryResult.cleaned);
        expect(fs.deletedPaths, contains(path));
        expect(inspect.callCount, 1);
      },
    );

    test('refuses to delete unregistered final managed PDFs', () async {
      const unregisteredPath =
          r'C:\MARJIY\ManagedLibrary\files\DOC-0000002.pdf';
      final repo = _FakeRepo(
        roots: const CopyRoots(managedLibraryRoot: managedRoot),
      );
      final fs = _FakeFilesystem();
      final inspect = _FakeInspect(repo, fs);
      final useCase = CleanupRecoveryArtifacts(
        repository: repo,
        filesystem: fs,
        inspectStartupRecovery: inspect,
      );
      // Caller would not normally pass unregistered PDFs to CleanupRecoveryArtifacts,
      // but even if passed in copyingFiles, name validation must reject it.
      final summary = RecoveryArtifactSummary(
        copyingFiles: const [unregisteredPath],
      );

      final result = await useCase(summary);

      expect(result, CleanupRecoveryResult.failed);
      expect(fs.deletedPaths, isEmpty);
      expect(inspect.callCount, 1);
    });

    test('refuses to delete files nested in subdirectories', () async {
      const nestedPath =
          r'C:\MARJIY\ManagedLibrary\files\sub\DOC-0000002.pdf.copy_abc.copying';
      final repo = _FakeRepo(
        roots: const CopyRoots(managedLibraryRoot: managedRoot),
      );
      final fs = _FakeFilesystem();
      final inspect = _FakeInspect(repo, fs);
      final useCase = CleanupRecoveryArtifacts(
        repository: repo,
        filesystem: fs,
        inspectStartupRecovery: inspect,
      );
      final summary = RecoveryArtifactSummary(copyingFiles: const [nestedPath]);

      final result = await useCase(summary);

      expect(result, CleanupRecoveryResult.failed);
      expect(fs.deletedPaths, isEmpty);
    });

    test(
      'refuses to delete files outside the managed files directory',
      () async {
        const outsidePath =
            r'C:\SomeOtherFolder\DOC-0000002.pdf.copy_abc.copying';
        final repo = _FakeRepo(
          roots: const CopyRoots(managedLibraryRoot: managedRoot),
        );
        final fs = _FakeFilesystem();
        final inspect = _FakeInspect(repo, fs);
        final useCase = CleanupRecoveryArtifacts(
          repository: repo,
          filesystem: fs,
          inspectStartupRecovery: inspect,
        );
        final summary = RecoveryArtifactSummary(
          copyingFiles: const [outsidePath],
        );

        final result = await useCase(summary);

        expect(result, CleanupRecoveryResult.failed);
        expect(fs.deletedPaths, isEmpty);
      },
    );

    test('refuses backup file in wrong root', () async {
      const wrongRootPath =
          r'C:\SomeOtherFolder\legal_library_backup_2026-06-21_120000_manual.sqlite';
      final repo = _FakeRepo(roots: const CopyRoots(backupRoot: backupRoot));
      final fs = _FakeFilesystem();
      final inspect = _FakeInspect(repo, fs);
      final useCase = CleanupRecoveryArtifacts(
        repository: repo,
        filesystem: fs,
        inspectStartupRecovery: inspect,
      );
      final summary = RecoveryArtifactSummary(
        incompleteBackups: const [wrongRootPath],
      );

      final result = await useCase(summary);

      expect(result, CleanupRecoveryResult.failed);
      expect(fs.deletedPaths, isEmpty);
    });

    test('refuses malformed .copying name (missing DOC code prefix)', () async {
      const malformedPath =
          r'C:\MARJIY\ManagedLibrary\files\random_file.pdf.copy_abc.copying';
      final repo = _FakeRepo(
        roots: const CopyRoots(managedLibraryRoot: managedRoot),
      );
      final fs = _FakeFilesystem();
      final inspect = _FakeInspect(repo, fs);
      final useCase = CleanupRecoveryArtifacts(
        repository: repo,
        filesystem: fs,
        inspectStartupRecovery: inspect,
      );
      final summary = RecoveryArtifactSummary(
        copyingFiles: const [malformedPath],
      );

      final result = await useCase(summary);

      expect(result, CleanupRecoveryResult.failed);
      expect(fs.deletedPaths, isEmpty);
    });

    test(
      'returns nothingToClean when summary has no eligible artifacts',
      () async {
        final repo = _FakeRepo(roots: const CopyRoots());
        final fs = _FakeFilesystem();
        final inspect = _FakeInspect(repo, fs);
        final useCase = CleanupRecoveryArtifacts(
          repository: repo,
          filesystem: fs,
          inspectStartupRecovery: inspect,
        );
        final summary = RecoveryArtifactSummary(
          unregisteredFinalPdfs: const [
            r'C:\MARJIY\ManagedLibrary\files\DOC-0000001.pdf',
          ],
        );

        final result = await useCase(summary);

        expect(result, CleanupRecoveryResult.nothingToClean);
        expect(fs.deletedPaths, isEmpty);
      },
    );

    test(
      'reports partialFailure when some deletions succeed and some fail',
      () async {
        const good =
            r'C:\MARJIY\ManagedLibrary\files\DOC-0000001.pdf.copy_a.copying';
        const bad =
            r'C:\MARJIY\ManagedLibrary\files\DOC-0000002.pdf.copy_b.copying';
        final repo = _FakeRepo(
          roots: const CopyRoots(managedLibraryRoot: managedRoot),
        );
        final fs = _FakeFilesystem()
          ..deletionResults[good] = const FilesystemSuccess()
          ..deletionResults[bad] = const FilesystemFailure(
            safeMessage: 'locked',
          );
        final inspect = _FakeInspect(repo, fs);
        final useCase = CleanupRecoveryArtifacts(
          repository: repo,
          filesystem: fs,
          inspectStartupRecovery: inspect,
        );
        final summary = RecoveryArtifactSummary(
          copyingFiles: const [good, bad],
        );

        final result = await useCase(summary);

        expect(result, CleanupRecoveryResult.partialFailure);
        expect(fs.deletedPaths, contains(good));
        expect(fs.deletedPaths, isNot(contains(bad)));
      },
    );

    test('reports failed when all deletions fail', () async {
      const path =
          r'C:\MARJIY\ManagedLibrary\files\DOC-0000001.pdf.copy_a.copying';
      final repo = _FakeRepo(
        roots: const CopyRoots(managedLibraryRoot: managedRoot),
      );
      final fs = _FakeFilesystem()
        ..deletionResults[path] = const FilesystemFailure(
          safeMessage: 'locked',
        );
      final inspect = _FakeInspect(repo, fs);
      final useCase = CleanupRecoveryArtifacts(
        repository: repo,
        filesystem: fs,
        inspectStartupRecovery: inspect,
      );
      final summary = RecoveryArtifactSummary(copyingFiles: const [path]);

      final result = await useCase(summary);

      expect(result, CleanupRecoveryResult.failed);
    });

    test('always calls inspectStartupRecovery after cleanup attempt', () async {
      final repo = _FakeRepo(roots: const CopyRoots());
      final fs = _FakeFilesystem();
      final inspect = _FakeInspect(repo, fs);
      final useCase = CleanupRecoveryArtifacts(
        repository: repo,
        filesystem: fs,
        inspectStartupRecovery: inspect,
      );

      await useCase(const RecoveryArtifactSummary());

      expect(inspect.callCount, 1);
    });

    test('does not delete when managed root is not configured', () async {
      const path =
          r'C:\MARJIY\ManagedLibrary\files\DOC-0000001.pdf.copy_a.copying';
      final repo = _FakeRepo(roots: const CopyRoots()); // no managedRoot
      final fs = _FakeFilesystem();
      final inspect = _FakeInspect(repo, fs);
      final useCase = CleanupRecoveryArtifacts(
        repository: repo,
        filesystem: fs,
        inspectStartupRecovery: inspect,
      );
      final summary = RecoveryArtifactSummary(copyingFiles: const [path]);

      final result = await useCase(summary);

      expect(result, CleanupRecoveryResult.failed);
      expect(fs.deletedPaths, isEmpty);
    });
  });
}

// ── Test doubles ──────────────────────────────────────────────────────────────

class _FakeRepo extends ManagedCopyRepository {
  _FakeRepo({required this.roots});

  final CopyRoots roots;
  StartupRecoveryStatus? savedStatus;

  @override
  Future<CopyRoots> loadCopyRoots() async => roots;

  @override
  Future<List<String>> loadManagedDocumentCodes() async => const [];

  @override
  Future<StartupRecoveryReport> loadStartupRecoveryReport() async =>
      StartupRecoveryReport.healthy;

  @override
  Future<void> saveStartupRecoveryReport(StartupRecoveryReport report) async {
    savedStatus = report.status;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFilesystem extends ManagedLibraryFilesystem {
  final deletedPaths = <String>[];
  final deletionResults = <String, FilesystemOperationResult>{};

  @override
  bool isExistingDirectory(String path) => true;

  @override
  Future<FilesystemOperationResult> deleteRecoveryArtifact(
    String path,
    String allowedRoot,
  ) async {
    final result = deletionResults[path] ?? const FilesystemSuccess();
    if (result is FilesystemSuccess) deletedPaths.add(path);
    return result;
  }

  @override
  Future<List<String>?> findStartupRecoveryArtifacts(
    String managedFilesDir,
    List<String> documentCodes,
  ) async => const [];

  @override
  Future<List<String>?> findStartupBackupArtifacts(String backupRoot) async =>
      const [];

  @override
  bool isExistingFile(String path) => false;

  @override
  Future<FilesystemOperationResult> ensureDirectoryExists(String path) =>
      throw UnimplementedError();

  @override
  Future<FilesystemOperationResult> copyFile(String src, String dst) =>
      throw UnimplementedError();

  @override
  Future<FilesystemOperationResult> finalizeFile(String tmp, String fin) =>
      throw UnimplementedError();

  @override
  Future<int?> fileSize(String path) => throw UnimplementedError();

  @override
  Future<List<String>?> findRecoveryArtifacts(String dir, String code) =>
      throw UnimplementedError();

  @override
  Future<FilesystemOperationResult> deleteFile(String path) =>
      throw UnimplementedError();
}

/// Fake [InspectStartupRecovery] that counts calls without real filesystem.
class _FakeInspect extends InspectStartupRecovery {
  _FakeInspect(_FakeRepo repo, _FakeFilesystem fs)
    : super(repository: repo, filesystem: fs);

  int callCount = 0;

  @override
  Future<StartupRecoveryReport> call() async {
    callCount++;
    return StartupRecoveryReport.healthy;
  }
}
