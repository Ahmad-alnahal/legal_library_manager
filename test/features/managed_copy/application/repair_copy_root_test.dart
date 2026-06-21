// test/features/managed_copy/application/repair_copy_root_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/managed_copy/application/repair_copy_root.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/copy_roots.dart';
import 'package:legal_library_manager/features/managed_copy/domain/repositories/managed_copy_repository.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/copy_root_picker.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/managed_library_filesystem.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/path_canonicalizer.dart';

String _norm(String value) =>
    value.replaceAll('/', r'\').toLowerCase().replaceFirst(RegExp(r'\\+$'), '');

class _FakeRepo implements ManagedCopyRepository {
  _FakeRepo({
    this._roots = const CopyRoots(),
    this.databaseRoot = r'C:\AppData\app',
    List<String>? sources,
  }) : sources = sources ?? <String>[];

  CopyRoots _roots;
  String databaseRoot;
  List<String> sources;

  int saveCount = 0;

  @override
  Future<CopyRoots> loadCopyRoots() async => _roots;

  @override
  Future<String> loadDatabaseRoot() async => databaseRoot;

  @override
  Future<List<String>> loadAllSourcePaths() async => sources;

  @override
  Future<void> saveCopyRoots({
    required String managedLibraryRoot,
    required String backupRoot,
  }) async {
    saveCount++;
    _roots = CopyRoots(
      managedLibraryRoot: managedLibraryRoot,
      backupRoot: backupRoot,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('$invocation');
}

/// In-memory directory model. Only directory existence and idempotent creation
/// are supported; every file-mutating boundary call is recorded as forbidden
/// (and never performed) so tests can assert repair never copies/moves/deletes.
class _FakeFilesystem implements ManagedLibraryFilesystem {
  _FakeFilesystem({Iterable<String> existing = const []}) {
    for (final dir in existing) {
      _existing.add(_norm(dir));
    }
  }

  final Set<String> _existing = <String>{};
  final List<String> createdNew = <String>[];
  final List<String> forbiddenCalls = <String>[];
  bool failCreation = false;

  @override
  bool isExistingDirectory(String path) => _existing.contains(_norm(path));

  @override
  Future<FilesystemOperationResult> ensureDirectoryExists(
    String absoluteDirPath,
  ) async {
    if (failCreation) {
      return const FilesystemFailure(safeMessage: 'Directory creation failed.');
    }
    final key = _norm(absoluteDirPath);
    if (!_existing.contains(key)) {
      _existing.add(key);
      createdNew.add(absoluteDirPath);
    }
    return const FilesystemSuccess();
  }

  // ── Forbidden during repair ────────────────────────────────────────────────

  @override
  bool isExistingFile(String path) {
    forbiddenCalls.add('isExistingFile');
    return false;
  }

  @override
  Future<FilesystemOperationResult> copyFile(String s, String d) async {
    forbiddenCalls.add('copyFile');
    return const FilesystemFailure(safeMessage: 'forbidden');
  }

  @override
  Future<FilesystemOperationResult> finalizeFile(String t, String f) async {
    forbiddenCalls.add('finalizeFile');
    return const FilesystemFailure(safeMessage: 'forbidden');
  }

  @override
  Future<int?> fileSize(String path) async {
    forbiddenCalls.add('fileSize');
    return null;
  }

  @override
  Future<List<String>?> findRecoveryArtifacts(String dir, String code) async {
    forbiddenCalls.add('findRecoveryArtifacts');
    return const [];
  }

  @override
  Future<List<String>?> findStartupRecoveryArtifacts(
    String managedFilesDir,
    List<String> documentCodes,
  ) async {
    forbiddenCalls.add('findStartupRecoveryArtifacts');
    return const [];
  }

  @override
  Future<List<String>?> findStartupBackupArtifacts(String backupRoot) async {
    forbiddenCalls.add('findStartupBackupArtifacts');
    return const [];
  }

  @override
  Future<FilesystemOperationResult> deleteFile(String path) async {
    forbiddenCalls.add('deleteFile');
    return const FilesystemSuccess();
  }
}

/// Identity canonicalizer with optional redirects (to simulate junctions that
/// resolve a path into a different — possibly protected — location).
class _FakeCanon implements PathCanonicalizer {
  _FakeCanon({this._redirects = const {}});

  final Map<String, String> _redirects;

  @override
  String? canonicalize(String path) => _redirects[path] ?? path;
}

RepairCopyRoot _build(
  _FakeRepo repo,
  _FakeFilesystem fs, {
  _FakeCanon? canon,
}) => RepairCopyRoot(repo, fs, canon ?? _FakeCanon());

void main() {
  group('successful repair', () {
    test('recreates only the missing managed root and revalidates', () async {
      final repo = _FakeRepo(
        roots: const CopyRoots(
          managedLibraryRoot: r'D:\Custom\Library',
          backupRoot: r'E:\Backups',
        ),
      );
      // Parent of the managed root exists; the leaf is missing. Backup exists.
      final fs = _FakeFilesystem(existing: const [r'D:\Custom', r'E:\Backups']);
      final repair = _build(repo, fs);

      final result = await repair(CopyRootKind.managedLibrary);

      expect(result, RepairCopyRootResult.repaired);
      // Only the exact configured root was created.
      expect(fs.createdNew, [r'D:\Custom\Library']);
      expect(fs.isExistingDirectory(r'D:\Custom\Library'), isTrue);
      // Repair never persists (the path is unchanged) and never mutates files.
      expect(repo.saveCount, 0);
      expect(fs.forbiddenCalls, isEmpty);
    });

    test('recreates only the missing backup root', () async {
      final repo = _FakeRepo(
        roots: const CopyRoots(
          managedLibraryRoot: r'C:\Managed',
          backupRoot: r'D:\Custom\Backups',
        ),
      );
      final fs = _FakeFilesystem(existing: const [r'C:\Managed', r'D:\Custom']);
      final repair = _build(repo, fs);

      final result = await repair(CopyRootKind.databaseBackup);

      expect(result, RepairCopyRootResult.repaired);
      expect(fs.createdNew, [r'D:\Custom\Backups']);
      expect(fs.forbiddenCalls, isEmpty);
    });

    test(
      'creates a multi-level missing chain for the exact root only',
      () async {
        final repo = _FakeRepo(
          roots: const CopyRoots(
            managedLibraryRoot: r'D:\A\B\C',
            backupRoot: r'E:\Backups',
          ),
        );
        final fs = _FakeFilesystem(existing: const [r'E:\Backups']);
        final repair = _build(repo, fs);

        final result = await repair(CopyRootKind.managedLibrary);

        expect(result, RepairCopyRootResult.repaired);
        expect(fs.createdNew, [r'D:\A', r'D:\A\B', r'D:\A\B\C']);
      },
    );
  });

  group('no-op outcomes', () {
    test('already-existing folder is not recreated', () async {
      final repo = _FakeRepo(
        roots: const CopyRoots(
          managedLibraryRoot: r'D:\Custom\Library',
          backupRoot: r'E:\Backups',
        ),
      );
      final fs = _FakeFilesystem(
        existing: const [r'D:\Custom\Library', r'E:\Backups'],
      );
      final repair = _build(repo, fs);

      final result = await repair(CopyRootKind.managedLibrary);

      expect(result, RepairCopyRootResult.alreadyExists);
      expect(fs.createdNew, isEmpty);
      expect(fs.forbiddenCalls, isEmpty);
    });

    test('unconfigured root has nothing to repair', () async {
      final repo = _FakeRepo(roots: const CopyRoots(backupRoot: r'E:\Backups'));
      final fs = _FakeFilesystem(existing: const [r'E:\Backups']);
      final repair = _build(repo, fs);

      final result = await repair(CopyRootKind.managedLibrary);

      expect(result, RepairCopyRootResult.notConfigured);
      expect(fs.createdNew, isEmpty);
    });

    test('relative configured path is rejected without creation', () async {
      final repo = _FakeRepo(
        roots: const CopyRoots(
          managedLibraryRoot: r'relative\library',
          backupRoot: r'E:\Backups',
        ),
      );
      final fs = _FakeFilesystem(existing: const [r'E:\Backups']);
      final repair = _build(repo, fs);

      final result = await repair(CopyRootKind.managedLibrary);

      expect(result, RepairCopyRootResult.invalidPath);
      expect(fs.createdNew, isEmpty);
    });
  });

  group('safety validation blocks repair', () {
    test('overlap with the database root prevents creation', () async {
      final repo = _FakeRepo(
        roots: const CopyRoots(
          managedLibraryRoot: r'C:\AppData\app\Library',
          backupRoot: r'E:\Backups',
        ),
        databaseRoot: r'C:\AppData\app',
      );
      final fs = _FakeFilesystem(
        existing: const [r'C:\AppData\app', r'E:\Backups'],
      );
      final repair = _build(repo, fs);

      final result = await repair(CopyRootKind.managedLibrary);

      expect(result, RepairCopyRootResult.unsafeOverlap);
      expect(fs.createdNew, isEmpty);
    });

    test('overlap with the other configured root prevents creation', () async {
      final repo = _FakeRepo(
        roots: const CopyRoots(
          managedLibraryRoot: r'D:\Shared',
          backupRoot: r'D:\Shared\Backups',
        ),
      );
      final fs = _FakeFilesystem(
        existing: const [r'D:\', r'D:\Shared\Backups'],
      );
      final repair = _build(repo, fs);

      final result = await repair(CopyRootKind.managedLibrary);

      expect(result, RepairCopyRootResult.unsafeOverlap);
      expect(fs.createdNew, isEmpty);
    });

    test('overlap with a registered source folder prevents creation', () async {
      final repo = _FakeRepo(
        roots: const CopyRoots(
          managedLibraryRoot: r'D:\Custom\Library',
          backupRoot: r'E:\Backups',
        ),
        sources: [r'D:\Custom\Library\src\a.pdf'],
      );
      final fs = _FakeFilesystem(existing: const [r'D:\Custom', r'E:\Backups']);
      final repair = _build(repo, fs);

      final result = await repair(CopyRootKind.managedLibrary);

      expect(result, RepairCopyRootResult.unsafeOverlap);
      expect(fs.createdNew, isEmpty);
      expect(fs.forbiddenCalls, isEmpty);
    });

    test(
      'a junction on an existing ancestor is rejected before creation',
      () async {
        // The existing parent resolves (canonically) into the database root.
        final repo = _FakeRepo(
          roots: const CopyRoots(
            managedLibraryRoot: r'D:\Custom\Library',
            backupRoot: r'E:\Backups',
          ),
          databaseRoot: r'C:\AppData\app',
        );
        final fs = _FakeFilesystem(
          existing: const [r'D:\Custom', r'E:\Backups'],
        );
        final canon = _FakeCanon(
          redirects: {r'D:\Custom': r'C:\AppData\app\redirected'},
        );
        final repair = _build(repo, fs, canon: canon);

        final result = await repair(CopyRootKind.managedLibrary);

        expect(result, RepairCopyRootResult.unsafeOverlap);
        expect(fs.createdNew, isEmpty);
      },
    );

    test('a junction discovered only after creation keeps it unsafe', () async {
      // Pre-creation literal checks pass; the created directory canonicalizes
      // into the database root, so post-creation revalidation blocks.
      final repo = _FakeRepo(
        roots: const CopyRoots(
          managedLibraryRoot: r'D:\Custom\Library',
          backupRoot: r'E:\Backups',
        ),
        databaseRoot: r'C:\AppData\app',
      );
      final fs = _FakeFilesystem(existing: const [r'D:\Custom', r'E:\Backups']);
      final canon = _FakeCanon(
        redirects: {r'D:\Custom\Library': r'C:\AppData\app\inside'},
      );
      final repair = _build(repo, fs, canon: canon);

      final result = await repair(CopyRootKind.managedLibrary);

      expect(result, RepairCopyRootResult.unsafeOverlap);
      // The directory was created but never deleted/altered (no mutation).
      expect(fs.forbiddenCalls, isEmpty);
    });
  });

  group('failure handling', () {
    test('a directory-creation failure yields creationFailed', () async {
      final repo = _FakeRepo(
        roots: const CopyRoots(
          managedLibraryRoot: r'D:\Custom\Library',
          backupRoot: r'E:\Backups',
        ),
      );
      final fs = _FakeFilesystem(existing: const [r'D:\Custom', r'E:\Backups'])
        ..failCreation = true;
      final repair = _build(repo, fs);

      final result = await repair(CopyRootKind.managedLibrary);

      expect(result, RepairCopyRootResult.creationFailed);
      expect(fs.isExistingDirectory(r'D:\Custom\Library'), isFalse);
    });
  });
}
