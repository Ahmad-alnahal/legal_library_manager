// test/features/managed_copy/application/inspect_startup_recovery_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/managed_copy/application/inspect_startup_recovery.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/copy_roots.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/startup_recovery_report.dart';
import 'package:legal_library_manager/features/managed_copy/domain/repositories/managed_copy_repository.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/managed_library_filesystem.dart';

void main() {
  group('InspectStartupRecovery', () {
    test('records healthy when no managed root is configured yet', () async {
      final repo = _FakeRepo(roots: const CopyRoots());
      final fs = _FakeFilesystem();
      final inspect = InspectStartupRecovery(repository: repo, filesystem: fs);

      final report = await inspect();

      expect(report.status, StartupRecoveryStatus.healthy);
      expect(repo.savedStatus, StartupRecoveryStatus.healthy);
      expect(fs.inspectedDirs, isEmpty);
    });

    test('detects app-owned copying artifacts and records attention', () async {
      final repo = _FakeRepo(
        roots: const CopyRoots(managedLibraryRoot: r'C:\MARJIY\ManagedLibrary'),
        documentCodes: const ['DOC-0000001'],
      );
      final fs = _FakeFilesystem()
        ..existingDirectories.addAll({
          r'C:\MARJIY\ManagedLibrary',
          r'C:\MARJIY\ManagedLibrary\files',
        })
        ..artifacts = const [
          r'C:\MARJIY\ManagedLibrary\files\DOC-0000001.pdf.copy_abc.copying',
        ];
      final inspect = InspectStartupRecovery(repository: repo, filesystem: fs);

      final report = await inspect();

      expect(report.status, StartupRecoveryStatus.requiresAttention);
      expect(report.artifactCount, 1);
      expect(repo.savedStatus, StartupRecoveryStatus.requiresAttention);
      expect(repo.savedArtifactCount, 1);
    });

    test('detects suspicious database backup artifacts', () async {
      final repo = _FakeRepo(
        roots: const CopyRoots(backupRoot: r'C:\MARJIY\DatabaseBackups'),
      );
      final fs = _FakeFilesystem()
        ..existingDirectories.add(r'C:\MARJIY\DatabaseBackups')
        ..backupArtifacts = const [
          r'C:\MARJIY\DatabaseBackups\legal_library_backup_2026-06-21_164400_manual.sqlite',
        ];
      final inspect = InspectStartupRecovery(repository: repo, filesystem: fs);

      final report = await inspect();

      expect(report.status, StartupRecoveryStatus.requiresAttention);
      expect(report.artifactCount, 1);
      expect(repo.savedStatus, StartupRecoveryStatus.requiresAttention);
      expect(repo.savedArtifactCount, 1);
      expect(fs.inspectedDirs, contains(r'C:\MARJIY\DatabaseBackups'));
    });

    test(
      'fails closed when managed files directory cannot be inspected',
      () async {
        final repo = _FakeRepo(
          roots: const CopyRoots(
            managedLibraryRoot: r'C:\MARJIY\ManagedLibrary',
          ),
          documentCodes: const ['DOC-0000001'],
        );
        final fs = _FakeFilesystem()
          ..existingDirectories.addAll({
            r'C:\MARJIY\ManagedLibrary',
            r'C:\MARJIY\ManagedLibrary\files',
          })
          ..artifacts = null;
        final inspect = InspectStartupRecovery(
          repository: repo,
          filesystem: fs,
        );

        final report = await inspect();

        expect(report.status, StartupRecoveryStatus.inspectionFailed);
        expect(report.requiresAttention, isTrue);
        expect(repo.savedStatus, StartupRecoveryStatus.inspectionFailed);
      },
    );
  });
}

class _FakeRepo extends ManagedCopyRepository {
  _FakeRepo({required this.roots, this.documentCodes = const []});

  final CopyRoots roots;
  final List<String> documentCodes;
  StartupRecoveryStatus? savedStatus;
  int? savedArtifactCount;

  @override
  Future<CopyRoots> loadCopyRoots() async => roots;

  @override
  Future<List<String>> loadManagedDocumentCodes() async => documentCodes;

  @override
  Future<void> saveStartupRecoveryReport(StartupRecoveryReport report) async {
    savedStatus = report.status;
    savedArtifactCount = report.artifactCount;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFilesystem implements ManagedLibraryFilesystem {
  final existingDirectories = <String>{};
  final inspectedDirs = <String>[];
  List<String>? artifacts = const [];
  List<String>? backupArtifacts = const [];

  @override
  bool isExistingDirectory(String path) => existingDirectories.contains(path);

  @override
  Future<List<String>?> findStartupRecoveryArtifacts(
    String managedFilesDir,
    List<String> documentCodes,
  ) async {
    inspectedDirs.add(managedFilesDir);
    return artifacts;
  }

  @override
  Future<List<String>?> findStartupBackupArtifacts(String backupRoot) async {
    inspectedDirs.add(backupRoot);
    return backupArtifacts;
  }

  @override
  bool isExistingFile(String path) => throw UnimplementedError();

  @override
  Future<FilesystemOperationResult> ensureDirectoryExists(
    String absoluteDirPath,
  ) => throw UnimplementedError();

  @override
  Future<FilesystemOperationResult> copyFile(
    String sourcePath,
    String destPath,
  ) => throw UnimplementedError();

  @override
  Future<FilesystemOperationResult> finalizeFile(
    String tmpPath,
    String finalPath,
  ) => throw UnimplementedError();

  @override
  Future<int?> fileSize(String path) => throw UnimplementedError();

  @override
  Future<List<String>?> findRecoveryArtifacts(
    String managedFilesDir,
    String documentCode,
  ) => throw UnimplementedError();

  @override
  Future<FilesystemOperationResult> deleteFile(String path) =>
      throw UnimplementedError();
}
