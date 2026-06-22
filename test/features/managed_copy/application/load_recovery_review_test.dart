// test/features/managed_copy/application/load_recovery_review_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/managed_copy/application/load_recovery_review.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/copy_roots.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/startup_recovery_report.dart';
import 'package:legal_library_manager/features/managed_copy/domain/repositories/managed_copy_repository.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/managed_library_filesystem.dart';

void main() {
  const managedRoot = r'C:\MARJIY\ManagedLibrary';
  const filesDir = r'C:\MARJIY\ManagedLibrary\files';
  const backupRoot = r'C:\MARJIY\DatabaseBackups';

  group('LoadRecoveryReview', () {
    test('returns empty summary when no roots are configured', () async {
      final repo = _FakeRepo(roots: const CopyRoots());
      final fs = _FakeFilesystem();
      final useCase = LoadRecoveryReview(repository: repo, filesystem: fs);

      final summary = await useCase();

      expect(summary, isNotNull);
      expect(summary!.copyingFiles, isEmpty);
      expect(summary.unregisteredFinalPdfs, isEmpty);
      expect(summary.incompleteBackups, isEmpty);
    });

    test('categorizes .copying file as eligible for cleanup', () async {
      final repo = _FakeRepo(
        roots: const CopyRoots(managedLibraryRoot: managedRoot),
        documentCodes: const ['DOC-0000001'],
      );
      const copyingPath =
          r'C:\MARJIY\ManagedLibrary\files\DOC-0000002.pdf.copy_abc.copying';
      final fs = _FakeFilesystem()
        ..existingDirs.addAll({managedRoot, filesDir})
        ..managedArtifacts = const [copyingPath];
      final useCase = LoadRecoveryReview(repository: repo, filesystem: fs);

      final summary = await useCase();

      expect(summary, isNotNull);
      expect(summary!.copyingFiles, contains(copyingPath));
      expect(summary.unregisteredFinalPdfs, isEmpty);
      expect(summary.incompleteBackups, isEmpty);
    });

    test('categorizes unregistered final PDF as manual-review-only', () async {
      final repo = _FakeRepo(
        roots: const CopyRoots(managedLibraryRoot: managedRoot),
        documentCodes: const ['DOC-0000001'],
      );
      const unregisteredPath =
          r'C:\MARJIY\ManagedLibrary\files\DOC-0000002.pdf';
      final fs = _FakeFilesystem()
        ..existingDirs.addAll({managedRoot, filesDir})
        ..managedArtifacts = const [unregisteredPath];
      final useCase = LoadRecoveryReview(repository: repo, filesystem: fs);

      final summary = await useCase();

      expect(summary, isNotNull);
      expect(summary!.unregisteredFinalPdfs, contains(unregisteredPath));
      expect(summary.copyingFiles, isEmpty);
      expect(summary.incompleteBackups, isEmpty);
    });

    test('categorizes incomplete backup file as eligible for cleanup', () async {
      final repo = _FakeRepo(roots: const CopyRoots(backupRoot: backupRoot));
      const backupPath =
          r'C:\MARJIY\DatabaseBackups\legal_library_backup_2026-06-21_120000_manual.sqlite';
      final fs = _FakeFilesystem()
        ..existingDirs.add(backupRoot)
        ..backupArtifacts = const [backupPath];
      final useCase = LoadRecoveryReview(repository: repo, filesystem: fs);

      final summary = await useCase();

      expect(summary, isNotNull);
      expect(summary!.incompleteBackups, contains(backupPath));
      expect(summary.copyingFiles, isEmpty);
      expect(summary.unregisteredFinalPdfs, isEmpty);
    });

    test('mixes all three categories correctly', () async {
      final repo = _FakeRepo(
        roots: const CopyRoots(
          managedLibraryRoot: managedRoot,
          backupRoot: backupRoot,
        ),
        documentCodes: const ['DOC-0000001'],
      );
      const copyingPath =
          r'C:\MARJIY\ManagedLibrary\files\DOC-0000002.pdf.copy_xyz.copying';
      const unregisteredPath =
          r'C:\MARJIY\ManagedLibrary\files\DOC-0000003.pdf';
      const backupPath =
          r'C:\MARJIY\DatabaseBackups\legal_library_backup_2026-06-21_120000_manual.sqlite';
      final fs = _FakeFilesystem()
        ..existingDirs.addAll({managedRoot, filesDir, backupRoot})
        ..managedArtifacts = const [copyingPath, unregisteredPath]
        ..backupArtifacts = const [backupPath];
      final useCase = LoadRecoveryReview(repository: repo, filesystem: fs);

      final summary = await useCase();

      expect(summary, isNotNull);
      expect(summary!.copyingFiles, contains(copyingPath));
      expect(summary.unregisteredFinalPdfs, contains(unregisteredPath));
      expect(summary.incompleteBackups, contains(backupPath));
      expect(summary.totalCount, 3);
      expect(summary.hasEligibleForCleanup, isTrue);
      expect(summary.hasManualReviewRequired, isTrue);
    });

    test(
      'returns null when managed files directory cannot be inspected',
      () async {
        final repo = _FakeRepo(
          roots: const CopyRoots(managedLibraryRoot: managedRoot),
          documentCodes: const ['DOC-0000001'],
        );
        final fs = _FakeFilesystem()
          ..existingDirs.addAll({managedRoot, filesDir})
          ..managedArtifacts = null; // null = inspection failed
        final useCase = LoadRecoveryReview(repository: repo, filesystem: fs);

        final summary = await useCase();

        expect(summary, isNull);
      },
    );

    test('returns null when backup directory cannot be inspected', () async {
      final repo = _FakeRepo(roots: const CopyRoots(backupRoot: backupRoot));
      final fs = _FakeFilesystem()
        ..existingDirs.add(backupRoot)
        ..backupArtifacts = null; // null = inspection failed
      final useCase = LoadRecoveryReview(repository: repo, filesystem: fs);

      final summary = await useCase();

      expect(summary, isNull);
    });

    test('does not inspect missing managed files directory', () async {
      final repo = _FakeRepo(
        roots: const CopyRoots(managedLibraryRoot: managedRoot),
      );
      final fs =
          _FakeFilesystem(); // existingDirs is empty → dir does not exist
      final useCase = LoadRecoveryReview(repository: repo, filesystem: fs);

      final summary = await useCase();

      expect(summary, isNotNull);
      expect(summary!.copyingFiles, isEmpty);
      expect(fs.inspectedManagedDirs, isEmpty);
    });

    test(
      'hasEligibleForCleanup is false when only unregistered PDFs present',
      () async {
        final repo = _FakeRepo(
          roots: const CopyRoots(managedLibraryRoot: managedRoot),
          documentCodes: const [],
        );
        const unregisteredPath =
            r'C:\MARJIY\ManagedLibrary\files\DOC-0000001.pdf';
        final fs = _FakeFilesystem()
          ..existingDirs.addAll({managedRoot, filesDir})
          ..managedArtifacts = const [unregisteredPath];
        final useCase = LoadRecoveryReview(repository: repo, filesystem: fs);

        final summary = await useCase();

        expect(summary, isNotNull);
        expect(summary!.hasEligibleForCleanup, isFalse);
        expect(summary.hasManualReviewRequired, isTrue);
      },
    );
  });
}

// ── Test doubles ──────────────────────────────────────────────────────────────

class _FakeRepo extends ManagedCopyRepository {
  _FakeRepo({required this.roots, this.documentCodes = const []});

  final CopyRoots roots;
  final List<String> documentCodes;

  @override
  Future<CopyRoots> loadCopyRoots() async => roots;

  @override
  Future<List<String>> loadManagedDocumentCodes() async => documentCodes;

  @override
  Future<StartupRecoveryReport> loadStartupRecoveryReport() async =>
      StartupRecoveryReport.healthy;

  @override
  Future<void> saveStartupRecoveryReport(StartupRecoveryReport report) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeFilesystem extends ManagedLibraryFilesystem {
  final existingDirs = <String>{};
  final inspectedManagedDirs = <String>[];
  List<String>? managedArtifacts = const [];
  List<String>? backupArtifacts = const [];

  @override
  bool isExistingDirectory(String path) => existingDirs.contains(path);

  @override
  Future<List<String>?> findStartupRecoveryArtifacts(
    String managedFilesDir,
    List<String> documentCodes,
  ) async {
    inspectedManagedDirs.add(managedFilesDir);
    return managedArtifacts;
  }

  @override
  Future<List<String>?> findStartupBackupArtifacts(String backupRoot) async {
    return backupArtifacts;
  }

  @override
  bool isExistingFile(String path) => throw UnimplementedError();

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
