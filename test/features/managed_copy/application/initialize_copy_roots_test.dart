// test/features/managed_copy/application/initialize_copy_roots_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/managed_copy/application/configure_copy_roots.dart';
import 'package:legal_library_manager/features/managed_copy/application/initialize_copy_roots.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/copy_roots.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/copy_roots_setup_report.dart';
import 'package:legal_library_manager/features/managed_copy/domain/repositories/managed_copy_repository.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/documents_directory_resolver.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/managed_library_filesystem.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/path_canonicalizer.dart';

// Stable default paths derived from the fake Documents directory, computed the
// same way InitializeCopyRoots does (`<Documents>\MARJIY\<root>`).
const String _docs = r'C:\Users\me\Documents';
const String _marjiy = r'C:\Users\me\Documents\MARJIY';
const String _defManaged = r'C:\Users\me\Documents\MARJIY\ManagedLibrary';
const String _defBackup = r'C:\Users\me\Documents\MARJIY\DatabaseBackups';

String _norm(String value) =>
    value.replaceAll('/', r'\').toLowerCase().replaceFirst(RegExp(r'\\+$'), '');

/// Records persistence calls and serves configurable roots/sources. Updating
/// [_roots] inside [saveCopyRoots] lets a second `call()` observe the persisted
/// state, so idempotency can be verified by invoking initialization twice.
class _FakeRepo implements ManagedCopyRepository {
  _FakeRepo({
    this._roots = const CopyRoots(),
    this.databaseRoot = r'C:\AppData\Roaming\app',
    List<String>? sources,
  }) : sources = sources ?? <String>[];

  CopyRoots _roots;
  String databaseRoot;
  List<String> sources;

  int saveCount = 0;
  String? savedManaged;
  String? savedBackup;

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
    savedManaged = managedLibraryRoot;
    savedBackup = backupRoot;
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
/// are supported; any file-mutating call is recorded as forbidden (and never
/// performed) so tests can assert initialization never copies/moves/deletes.
class _FakeFilesystem implements ManagedLibraryFilesystem {
  _FakeFilesystem({Iterable<String> existing = const []}) {
    for (final dir in existing) {
      _existing.add(_norm(dir));
    }
  }

  final Set<String> _existing = <String>{};

  /// Paths passed to ensureDirectoryExists, in order.
  final List<String> ensureCalls = <String>[];

  /// Paths that did not exist and were newly created.
  final List<String> createdNew = <String>[];

  /// Names of any file-mutating boundary methods that were invoked.
  final List<String> forbiddenCalls = <String>[];

  /// When true, every ensureDirectoryExists call reports a safe failure.
  bool failCreation = false;

  @override
  bool isExistingDirectory(String path) => _existing.contains(_norm(path));

  @override
  Future<FilesystemOperationResult> ensureDirectoryExists(
    String absoluteDirPath,
  ) async {
    ensureCalls.add(absoluteDirPath);
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

  // ── Forbidden during automatic initialization ──────────────────────────────

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
  Future<FilesystemOperationResult> deleteFile(String path) async {
    forbiddenCalls.add('deleteFile');
    return const FilesystemSuccess();
  }
}

class _IdentityCanonicalizer implements PathCanonicalizer {
  @override
  String? canonicalize(String path) => path;
}

class _FakeResolver implements DocumentsDirectoryResolver {
  _FakeResolver({this.path = _docs, this.throwError = false});
  final String? path;
  final bool throwError;

  @override
  Future<String?> resolveDocumentsPath() async {
    if (throwError) throw StateError('documents unavailable');
    return path;
  }
}

InitializeCopyRoots _build(
  _FakeRepo repo,
  _FakeFilesystem fs,
  _FakeResolver resolver,
) {
  final configure = ConfigureCopyRoots(repo, fs, _IdentityCanonicalizer());
  return InitializeCopyRoots(
    repository: repo,
    filesystem: fs,
    documentsResolver: resolver,
    configureCopyRoots: configure,
  );
}

void main() {
  group('first startup — neither root configured', () {
    test('creates and persists both defaults', () async {
      final repo = _FakeRepo();
      final fs = _FakeFilesystem(existing: const [_docs]);
      final init = _build(repo, fs, _FakeResolver());

      final report = await init();

      expect(report.outcome, CopyRootsSetupOutcome.defaultsCreated);
      expect(report.managedRoot, _defManaged);
      expect(report.backupRoot, _defBackup);
      expect(report.managedStatus, CopyRootStatus.automatic);
      expect(report.backupStatus, CopyRootStatus.automatic);
      expect(report.requiresAttention, isFalse);

      // Persisted exactly once, with the default paths.
      expect(repo.saveCount, 1);
      expect(repo.savedManaged, _defManaged);
      expect(repo.savedBackup, _defBackup);

      // Both roots (and the MARJIY parent) now exist.
      expect(fs.isExistingDirectory(_marjiy), isTrue);
      expect(fs.isExistingDirectory(_defManaged), isTrue);
      expect(fs.isExistingDirectory(_defBackup), isTrue);
    });

    test(
      'only ever creates directories — never copies/moves/deletes',
      () async {
        final repo = _FakeRepo();
        final fs = _FakeFilesystem(existing: const [_docs]);
        final init = _build(repo, fs, _FakeResolver());

        await init();

        expect(fs.forbiddenCalls, isEmpty);
      },
    );
  });

  group('repeated startup', () {
    test(
      'is idempotent: second run persists nothing and changes nothing',
      () async {
        final repo = _FakeRepo();
        final fs = _FakeFilesystem(existing: const [_docs]);
        final init = _build(repo, fs, _FakeResolver());

        final first = await init();
        expect(first.outcome, CopyRootsSetupOutcome.defaultsCreated);
        final createdAfterFirst = List<String>.from(fs.createdNew);

        final second = await init();

        expect(second.outcome, CopyRootsSetupOutcome.alreadyConfigured);
        expect(second.managedStatus, CopyRootStatus.automatic);
        expect(second.backupStatus, CopyRootStatus.automatic);
        // No additional persistence and no additional directory creation.
        expect(repo.saveCount, 1);
        expect(fs.createdNew, createdAfterFirst);
        expect(fs.forbiddenCalls, isEmpty);
      },
    );
  });

  group('existing configuration', () {
    test('valid custom roots remain unchanged', () async {
      const customManaged = r'D:\Custom\Library';
      const customBackup = r'E:\Custom\Backups';
      final repo = _FakeRepo(
        roots: const CopyRoots(
          managedLibraryRoot: customManaged,
          backupRoot: customBackup,
        ),
      );
      final fs = _FakeFilesystem(
        existing: const [_docs, customManaged, customBackup],
      );
      final init = _build(repo, fs, _FakeResolver());

      final report = await init();

      expect(report.outcome, CopyRootsSetupOutcome.alreadyConfigured);
      expect(report.managedRoot, customManaged);
      expect(report.backupRoot, customBackup);
      expect(report.managedStatus, CopyRootStatus.custom);
      expect(report.backupStatus, CopyRootStatus.custom);
      expect(repo.saveCount, 0);
      expect(fs.createdNew, isEmpty);
      expect(fs.forbiddenCalls, isEmpty);
    });

    test(
      'missing default directories are recreated without re-persisting',
      () async {
        // Both roots persisted at the default paths, but the directories are gone.
        final repo = _FakeRepo(
          roots: const CopyRoots(
            managedLibraryRoot: _defManaged,
            backupRoot: _defBackup,
          ),
        );
        final fs = _FakeFilesystem(existing: const [_docs]);
        final init = _build(repo, fs, _FakeResolver());

        final report = await init();

        expect(report.outcome, CopyRootsSetupOutcome.defaultRecreated);
        expect(report.managedStatus, CopyRootStatus.automatic);
        expect(report.backupStatus, CopyRootStatus.automatic);
        // Paths were unchanged, so nothing is re-persisted.
        expect(repo.saveCount, 0);
        // The default directories were recreated.
        expect(fs.isExistingDirectory(_defManaged), isTrue);
        expect(fs.isExistingDirectory(_defBackup), isTrue);
        expect(fs.forbiddenCalls, isEmpty);
      },
    );

    test(
      'missing custom directory requires attention and is not recreated',
      () async {
        const customManaged = r'D:\Custom\Library';
        final repo = _FakeRepo(
          roots: const CopyRoots(
            managedLibraryRoot: customManaged,
            backupRoot: _defBackup,
          ),
        );
        // The custom managed directory is absent; the default backup exists.
        final fs = _FakeFilesystem(
          existing: const [_docs, _marjiy, _defBackup],
        );
        final init = _build(repo, fs, _FakeResolver());

        final report = await init();

        expect(report.outcome, CopyRootsSetupOutcome.requiresAttention);
        expect(report.requiresAttention, isTrue);
        expect(report.managedStatus, CopyRootStatus.missing);
        expect(report.backupStatus, CopyRootStatus.automatic);
        expect(repo.saveCount, 0);
        // The custom directory was never (re)created.
        expect(fs.isExistingDirectory(customManaged), isFalse);
        expect(
          fs.ensureCalls.map(_norm),
          isNot(contains(_norm(customManaged))),
        );
      },
    );
  });

  group('exactly one root configured', () {
    test(
      'fills only the missing backup, leaving the custom managed root intact',
      () async {
        const customManaged = r'D:\Custom\Library';
        final repo = _FakeRepo(
          roots: const CopyRoots(managedLibraryRoot: customManaged),
        );
        final fs = _FakeFilesystem(existing: const [_docs, customManaged]);
        final init = _build(repo, fs, _FakeResolver());

        final report = await init();

        expect(report.outcome, CopyRootsSetupOutcome.missingRootFilled);
        expect(report.managedRoot, customManaged);
        expect(report.backupRoot, _defBackup);
        expect(report.managedStatus, CopyRootStatus.custom);
        expect(report.backupStatus, CopyRootStatus.automatic);
        // The existing root is re-persisted with its unchanged value.
        expect(repo.saveCount, 1);
        expect(repo.savedManaged, customManaged);
        expect(repo.savedBackup, _defBackup);
        expect(fs.isExistingDirectory(_defBackup), isTrue);
      },
    );

    test(
      'fills only the missing managed root when backup is configured',
      () async {
        const customBackup = r'E:\Custom\Backups';
        final repo = _FakeRepo(
          roots: const CopyRoots(backupRoot: customBackup),
        );
        final fs = _FakeFilesystem(existing: const [_docs, customBackup]);
        final init = _build(repo, fs, _FakeResolver());

        final report = await init();

        expect(report.outcome, CopyRootsSetupOutcome.missingRootFilled);
        expect(report.managedRoot, _defManaged);
        expect(report.backupRoot, customBackup);
        expect(report.managedStatus, CopyRootStatus.automatic);
        expect(report.backupStatus, CopyRootStatus.custom);
        expect(repo.savedManaged, _defManaged);
        expect(repo.savedBackup, customBackup);
      },
    );

    test(
      'requires attention when the existing custom root is missing',
      () async {
        const customManaged = r'D:\Custom\Library';
        final repo = _FakeRepo(
          roots: const CopyRoots(managedLibraryRoot: customManaged),
        );
        // The configured managed root's directory does not exist.
        final fs = _FakeFilesystem(existing: const [_docs]);
        final init = _build(repo, fs, _FakeResolver());

        final report = await init();

        expect(report.outcome, CopyRootsSetupOutcome.requiresAttention);
        expect(report.managedStatus, CopyRootStatus.missing);
        expect(report.backupStatus, CopyRootStatus.notConfigured);
        expect(repo.saveCount, 0);
      },
    );
  });

  group('safety validation blocks persistence', () {
    test(
      'unsafe overlap with the database root prevents persistence',
      () async {
        // Database root sits inside the default managed library → overlap.
        final repo = _FakeRepo(databaseRoot: '$_defManaged\\db');
        final fs = _FakeFilesystem(existing: const [_docs]);
        final init = _build(repo, fs, _FakeResolver());

        final report = await init();

        expect(report.outcome, CopyRootsSetupOutcome.requiresAttention);
        expect(repo.saveCount, 0);
      },
    );

    test('source-folder overlap prevents persistence', () async {
      // A registered source file lives under the default managed library.
      final repo = _FakeRepo(
        sources: [r'C:\Users\me\Documents\MARJIY\ManagedLibrary\src\a.pdf'],
      );
      final fs = _FakeFilesystem(existing: const [_docs]);
      final init = _build(repo, fs, _FakeResolver());

      final report = await init();

      expect(report.outcome, CopyRootsSetupOutcome.requiresAttention);
      expect(repo.saveCount, 0);
    });
  });

  group('startup never crashes on failures', () {
    test(
      'null Documents path yields requires-attention, not a throw',
      () async {
        final repo = _FakeRepo();
        final fs = _FakeFilesystem();
        final init = _build(repo, fs, _FakeResolver(path: null));

        final report = await init();

        expect(report.outcome, CopyRootsSetupOutcome.requiresAttention);
        expect(repo.saveCount, 0);
      },
    );

    test('a throwing Documents resolver is caught', () async {
      final repo = _FakeRepo();
      final fs = _FakeFilesystem();
      final init = _build(repo, fs, _FakeResolver(throwError: true));

      final report = await init();

      expect(report.outcome, CopyRootsSetupOutcome.requiresAttention);
      expect(repo.saveCount, 0);
    });

    test('a directory-creation failure yields requires-attention', () async {
      final repo = _FakeRepo();
      final fs = _FakeFilesystem(existing: const [_docs])..failCreation = true;
      final init = _build(repo, fs, _FakeResolver());

      final report = await init();

      expect(report.outcome, CopyRootsSetupOutcome.requiresAttention);
      expect(repo.saveCount, 0);
    });
  });
}
