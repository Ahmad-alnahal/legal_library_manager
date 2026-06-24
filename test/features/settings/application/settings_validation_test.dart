// test/features/settings/application/settings_validation_test.dart
//
// M10.2 acceptance: path-safety rules for managed-library and backup roots.
// These tests cover the cases required by M10.2 that are not already present in
// test/features/managed_copy/application/configure_copy_roots_test.dart.

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/managed_copy/application/configure_copy_roots.dart';
import 'package:legal_library_manager/features/managed_copy/domain/repositories/managed_copy_repository.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/managed_library_filesystem.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/path_canonicalizer.dart';
import 'package:legal_library_manager/features/security/application/session_manager.dart';
import 'package:legal_library_manager/features/security/domain/entities/account_role.dart';
import 'package:legal_library_manager/features/security/domain/entities/session.dart';

// ── Test doubles ──────────────────────────────────────────────────────────────

class _Repo implements ManagedCopyRepository {
  String databaseRoot = r'C:\AppSupport';
  List<String> sources = [];
  String? savedManaged;
  String? savedBackup;

  @override
  Future<String> loadDatabaseRoot() async => databaseRoot;

  @override
  Future<List<String>> loadAllSourcePaths() async => sources;

  @override
  Future<void> saveCopyRoots({
    required String managedLibraryRoot,
    required String backupRoot,
  }) async {
    savedManaged = managedLibraryRoot;
    savedBackup = backupRoot;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('$invocation');
}

class _Filesystem implements ManagedLibraryFilesystem {
  bool exists = true;

  @override
  bool isExistingDirectory(String path) => exists;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('$invocation');
}

class _Canonicalizer implements PathCanonicalizer {
  @override
  String? canonicalize(String path) => path;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

final _adminSession = Session(
  accountId: 'admin',
  username: 'marjiy@admin',
  role: AccountRole.admin,
  startedAt: DateTime.utc(2026, 6, 24, 9),
);

void main() {
  late _Repo repo;
  late _Filesystem filesystem;
  late SessionManager sessionManager;
  late ConfigureCopyRoots configure;

  setUp(() {
    repo = _Repo();
    filesystem = _Filesystem();
    sessionManager = SessionManager();
    sessionManager.login(_adminSession);
    configure = ConfigureCopyRoots(
      repo,
      filesystem,
      _Canonicalizer(),
      sessionManager: sessionManager,
    );
  });

  tearDown(() => sessionManager.dispose());

  group('settings path validation', () {
    // ── Identical roots ──────────────────────────────────────────────────────

    test('blocks identical managed and backup roots', () async {
      final result = await configure(r'C:\SameRoot', r'C:\SameRoot');
      expect(result, ConfigureCopyRootsResult.unsafeOverlap);
    });

    test('blocks case-insensitive identical roots on Windows', () async {
      final result = await configure(r'C:\MyRoot', r'c:\myroot');
      expect(result, ConfigureCopyRootsResult.unsafeOverlap);
    });

    // ── Managed / backup inside each other ───────────────────────────────────

    test('blocks backup root nested inside managed root', () async {
      final result = await configure(r'C:\Managed', r'C:\Managed\Backups');
      expect(result, ConfigureCopyRootsResult.unsafeOverlap);
    });

    test('blocks managed root nested inside backup root', () async {
      final result = await configure(r'C:\Backups\Managed', r'C:\Backups');
      expect(result, ConfigureCopyRootsResult.unsafeOverlap);
    });

    // ── Roots inside source import folders ───────────────────────────────────

    test(
      'blocks managed root nested inside a registered source import folder',
      () async {
        // source file is in C:\ImportedDocs — managed must not go inside that folder
        repo.sources = [r'C:\ImportedDocs\contract.pdf'];
        final result = await configure(
          r'C:\ImportedDocs\ManagedLib',
          r'D:\Backups',
        );
        expect(result, ConfigureCopyRootsResult.unsafeOverlap);
      },
    );

    test(
      'blocks backup root nested inside a registered source import folder',
      () async {
        repo.sources = [r'C:\Sources\report.pdf'];
        final result = await configure(r'D:\Managed', r'C:\Sources\Backups');
        expect(result, ConfigureCopyRootsResult.unsafeOverlap);
      },
    );

    // ── Source folders inside roots ───────────────────────────────────────────

    test('blocks source import folder nested inside managed root', () async {
      // source file is inside the managed root subtree — dangerous overlap
      repo.sources = [r'C:\Managed\ImportedDocs\contract.pdf'];
      final result = await configure(r'C:\Managed', r'D:\Backups');
      expect(result, ConfigureCopyRootsResult.unsafeOverlap);
    });

    test('blocks source import folder nested inside backup root', () async {
      repo.sources = [r'D:\Backups\ImportedDocs\report.pdf'];
      final result = await configure(r'C:\Managed', r'D:\Backups');
      expect(result, ConfigureCopyRootsResult.unsafeOverlap);
    });

    // ── Missing / inaccessible directories ───────────────────────────────────

    test('blocks non-existent managed directory', () async {
      filesystem.exists = false;
      final result = await configure(r'C:\DoesNotExist', r'D:\Backups');
      expect(result, ConfigureCopyRootsResult.invalidFolder);
    });

    test('blocks non-existent backup directory', () async {
      filesystem.exists = false;
      final result = await configure(r'C:\Managed', r'D:\DoesNotExist');
      expect(result, ConfigureCopyRootsResult.invalidFolder);
    });

    // ── Valid configuration ───────────────────────────────────────────────────

    test('allows valid separate non-overlapping roots', () async {
      final result = await configure(r'C:\Managed', r'D:\Backups');
      expect(result, ConfigureCopyRootsResult.saved);
      expect(repo.savedManaged, r'C:\Managed');
      expect(repo.savedBackup, r'D:\Backups');
    });

    test('allows roots on different drives with no source conflicts', () async {
      repo.sources = [r'E:\LegalArchive\doc.pdf'];
      final result = await configure(r'C:\ManagedLib', r'D:\DBBackups');
      expect(result, ConfigureCopyRootsResult.saved);
    });
  });
}
