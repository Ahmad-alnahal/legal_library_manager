// test/features/managed_copy/application/apply_default_copy_roots_test.dart
//
// Unit tests for ApplyDefaultCopyRoots — covers all ApplyDefaultCopyRootsResult
// branches without touching the filesystem or database.

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/managed_copy/application/apply_default_copy_roots.dart';
import 'package:legal_library_manager/features/managed_copy/application/configure_copy_roots.dart';
import 'package:legal_library_manager/features/managed_copy/domain/repositories/managed_copy_repository.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/documents_directory_resolver.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/managed_library_filesystem.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/path_canonicalizer.dart';
import 'package:legal_library_manager/features/security/application/session_manager.dart';
import 'package:legal_library_manager/features/security/application/step_up_manager.dart';
import 'package:legal_library_manager/features/security/domain/entities/account_role.dart';
import 'package:legal_library_manager/features/security/domain/entities/session.dart';

const String _kDocs = r'C:\Users\me\Documents';

class _FakeDocumentsResolver implements DocumentsDirectoryResolver {
  _FakeDocumentsResolver(this.path);
  final String? path;
  @override
  Future<String?> resolveDocumentsPath() async => path;
}

/// Filesystem used directly by [ApplyDefaultCopyRoots]. Only implements
/// [ensureDirectoryExists]; counts calls and can fail on a chosen call.
class _FakeApplyFilesystem implements ManagedLibraryFilesystem {
  _FakeApplyFilesystem({this.failOnCall});
  final int? failOnCall;
  int callCount = 0;

  @override
  Future<FilesystemOperationResult> ensureDirectoryExists(
    String absoluteDirPath,
  ) async {
    callCount++;
    if (failOnCall != null && callCount == failOnCall) {
      return const FilesystemFailure(safeMessage: 'access denied');
    }
    return const FilesystemSuccess();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('$invocation');
}

/// Filesystem used by the internal [ConfigureCopyRoots]. Only implements
/// [isExistingDirectory].
class _FilesystemForConfigure implements ManagedLibraryFilesystem {
  _FilesystemForConfigure({this.exists = true});
  final bool exists;

  @override
  bool isExistingDirectory(String path) => exists;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('$invocation');
}

class _Repo implements ManagedCopyRepository {
  _Repo({this.databaseRoot = r'C:\AppSupport'});
  String databaseRoot;
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

class _Canonicalizer implements PathCanonicalizer {
  @override
  String? canonicalize(String path) => path;
}

Session _session(AccountRole role) => Session(
  accountId: 'admin',
  username: 'marjiy@admin',
  role: role,
  startedAt: DateTime.utc(2026, 6, 24, 9),
);

void main() {
  late SessionManager sessionManager;
  late StepUpManager stepUpManager;

  setUp(() {
    stepUpManager = StepUpManager();
    sessionManager = SessionManager(
      adminTimeout: const Duration(hours: 1),
      stepUpManager: stepUpManager,
    );
  });

  tearDown(() {
    stepUpManager.dispose();
    sessionManager.dispose();
  });

  ApplyDefaultCopyRoots build({
    String? documentsPath,
    _FakeApplyFilesystem? applyFilesystem,
    _FilesystemForConfigure? configureFilesystem,
    _Repo? repo,
  }) {
    final configureFs = configureFilesystem ?? _FilesystemForConfigure();
    final configure = ConfigureCopyRoots(
      repo ?? _Repo(),
      configureFs,
      _Canonicalizer(),
      sessionManager: sessionManager,
      stepUpManager: stepUpManager,
    );
    return ApplyDefaultCopyRoots(
      documentsResolver: _FakeDocumentsResolver(documentsPath),
      filesystem: applyFilesystem ?? _FakeApplyFilesystem(),
      configureCopyRoots: configure,
      sessionManager: sessionManager,
      stepUpManager: stepUpManager,
    );
  }

  test('unauthorized when no active session', () async {
    final useCase = build(documentsPath: _kDocs);

    final result = await useCase();

    expect(result, ApplyDefaultCopyRootsResult.unauthorized);
  });

  test('unauthorized when session is a non-admin operator', () async {
    sessionManager.login(_session(AccountRole.operator));
    stepUpManager.grant();
    final useCase = build(documentsPath: _kDocs);

    final result = await useCase();

    expect(result, ApplyDefaultCopyRootsResult.unauthorized);
  });

  test('stepUpRequired when admin has no step-up approval', () async {
    sessionManager.login(_session(AccountRole.admin));
    final useCase = build(documentsPath: _kDocs);

    final result = await useCase();

    expect(result, ApplyDefaultCopyRootsResult.stepUpRequired);
  });

  test('documentsNotResolvable when resolver returns null', () async {
    sessionManager.login(_session(AccountRole.admin));
    stepUpManager.grant();
    final useCase = build(documentsPath: null);

    final result = await useCase();

    expect(result, ApplyDefaultCopyRootsResult.documentsNotResolvable);
  });

  test(
    'documentsNotResolvable when resolver returns only backslashes',
    () async {
      sessionManager.login(_session(AccountRole.admin));
      stepUpManager.grant();
      final useCase = build(documentsPath: r'\');

      final result = await useCase();

      expect(result, ApplyDefaultCopyRootsResult.documentsNotResolvable);
    },
  );

  test('directoryCreationFailed when MARJIY dir creation fails', () async {
    sessionManager.login(_session(AccountRole.admin));
    stepUpManager.grant();
    final useCase = build(
      documentsPath: _kDocs,
      applyFilesystem: _FakeApplyFilesystem(failOnCall: 1),
    );

    final result = await useCase();

    expect(result, ApplyDefaultCopyRootsResult.directoryCreationFailed);
  });

  test('directoryCreationFailed when backup dir creation fails', () async {
    sessionManager.login(_session(AccountRole.admin));
    stepUpManager.grant();
    final useCase = build(
      documentsPath: _kDocs,
      applyFilesystem: _FakeApplyFilesystem(failOnCall: 3),
    );

    final result = await useCase();

    expect(result, ApplyDefaultCopyRootsResult.directoryCreationFailed);
  });

  test('unsafeOverlap when default root overlaps the database root', () async {
    sessionManager.login(_session(AccountRole.admin));
    stepUpManager.grant();
    final useCase = build(
      documentsPath: _kDocs,
      configureFilesystem: _FilesystemForConfigure(exists: true),
      repo: _Repo(databaseRoot: r'C:\Users\me\Documents\MARJIY\ManagedLibrary'),
    );

    final result = await useCase();

    expect(result, ApplyDefaultCopyRootsResult.unsafeOverlap);
  });

  test(
    'configurationFailed when ConfigureCopyRoots reports invalidFolder',
    () async {
      sessionManager.login(_session(AccountRole.admin));
      stepUpManager.grant();
      final useCase = build(
        documentsPath: _kDocs,
        configureFilesystem: _FilesystemForConfigure(exists: false),
      );

      final result = await useCase();

      expect(result, ApplyDefaultCopyRootsResult.configurationFailed);
    },
  );

  test('applied on the full success path', () async {
    sessionManager.login(_session(AccountRole.admin));
    stepUpManager.grant();
    final repo = _Repo(databaseRoot: r'C:\AppSupport');
    final useCase = build(
      documentsPath: _kDocs,
      configureFilesystem: _FilesystemForConfigure(exists: true),
      repo: repo,
    );

    final result = await useCase();

    expect(result, ApplyDefaultCopyRootsResult.applied);
    expect(repo.savedManaged, r'C:\Users\me\Documents\MARJIY\ManagedLibrary');
    expect(repo.savedBackup, r'C:\Users\me\Documents\MARJIY\DatabaseBackups');
  });
}
