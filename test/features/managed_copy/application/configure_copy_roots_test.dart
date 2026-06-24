import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/managed_copy/application/configure_copy_roots.dart';
import 'package:legal_library_manager/features/managed_copy/domain/repositories/managed_copy_repository.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/managed_library_filesystem.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/path_canonicalizer.dart';
import 'package:legal_library_manager/features/security/application/session_manager.dart';
import 'package:legal_library_manager/features/security/domain/entities/account_role.dart';
import 'package:legal_library_manager/features/security/domain/entities/session.dart';

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

  test('returns unauthorized when no session is active', () async {
    final noSessionManager = SessionManager();
    final unauthConfigure = ConfigureCopyRoots(
      repo,
      filesystem,
      _Canonicalizer(),
      sessionManager: noSessionManager,
    );
    expect(
      await unauthConfigure(r'C:\Managed', r'D:\Backups'),
      ConfigureCopyRootsResult.unauthorized,
    );
    noSessionManager.dispose();
  });

  test('returns unauthorized when an operator session is active', () async {
    final operatorManager = SessionManager();
    operatorManager.login(Session(
      accountId: 'op1',
      username: 'op@operator',
      role: AccountRole.operator,
      startedAt: DateTime.utc(2026, 6, 24, 9),
    ));
    final unauthConfigure = ConfigureCopyRoots(
      repo,
      filesystem,
      _Canonicalizer(),
      sessionManager: operatorManager,
    );
    expect(
      await unauthConfigure(r'C:\Managed', r'D:\Backups'),
      ConfigureCopyRootsResult.unauthorized,
    );
    operatorManager.dispose();
  });

  test('saves separate existing safe roots', () async {
    final result = await configure(r'C:\Managed', r'D:\Backups');
    expect(result, ConfigureCopyRootsResult.saved);
    expect(repo.savedManaged, r'C:\Managed');
    expect(repo.savedBackup, r'D:\Backups');
  });

  test('requires both roots', () async {
    expect(
      await configure(r'C:\Managed', null),
      ConfigureCopyRootsResult.chooseBoth,
    );
  });

  test('blocks overlapping roots and database root', () async {
    expect(
      await configure(r'C:\Managed', r'C:\Managed\Backups'),
      ConfigureCopyRootsResult.unsafeOverlap,
    );
    expect(
      await configure(r'C:\AppSupport\Managed', r'D:\Backups'),
      ConfigureCopyRootsResult.unsafeOverlap,
    );
  });

  test('blocks roots that contain registered source folders', () async {
    repo.sources = [r'C:\Managed\Sources\doc.pdf'];
    expect(
      await configure(r'C:\Managed', r'D:\Backups'),
      ConfigureCopyRootsResult.unsafeOverlap,
    );
  });
}
