import '../../security/application/session_manager.dart';
import '../../security/application/step_up_manager.dart';
import '../../security/domain/entities/account_role.dart';
import '../domain/repositories/managed_copy_repository.dart';
import '../domain/services/managed_library_filesystem.dart';
import '../domain/services/path_canonicalizer.dart';

enum ConfigureCopyRootsResult {
  saved,
  chooseBoth,
  invalidFolder,
  unsafeOverlap,

  /// Caller does not hold an active administrator session.
  unauthorized,

  /// Caller is admin but has no active step-up authentication approval.
  stepUpRequired,
}

class ConfigureCopyRoots {
  const ConfigureCopyRoots(
    this._repository,
    this._filesystem,
    this._canonicalizer, {
    required this._sessionManager,
    required this._stepUpManager,
  });

  final ManagedCopyRepository _repository;
  final ManagedLibraryFilesystem _filesystem;
  final PathCanonicalizer _canonicalizer;
  final SessionManager _sessionManager;
  final StepUpManager _stepUpManager;

  Future<ConfigureCopyRootsResult> call(String? managed, String? backup) async {
    final session = _sessionManager.currentSession;
    if (session == null || session.role != AccountRole.admin) {
      return ConfigureCopyRootsResult.unauthorized;
    }
    if (!_stepUpManager.isApproved) {
      return ConfigureCopyRootsResult.stepUpRequired;
    }

    if (managed == null || backup == null) {
      return ConfigureCopyRootsResult.chooseBoth;
    }
    if (!_filesystem.isExistingDirectory(managed) ||
        !_filesystem.isExistingDirectory(backup)) {
      return ConfigureCopyRootsResult.invalidFolder;
    }
    final m = _canonicalizer.canonicalize(managed);
    final b = _canonicalizer.canonicalize(backup);
    final db = _canonicalizer.canonicalize(
      await _repository.loadDatabaseRoot(),
    );
    if (m == null || b == null || db == null) {
      return ConfigureCopyRootsResult.invalidFolder;
    }
    if (_overlap(m, b) || _overlap(m, db) || _overlap(b, db)) {
      return ConfigureCopyRootsResult.unsafeOverlap;
    }
    for (final sourcePath in await _repository.loadAllSourcePaths()) {
      final sourceParent = _canonicalizer.canonicalize(_parent(sourcePath));
      if (sourceParent == null ||
          _overlap(m, sourceParent) ||
          _overlap(b, sourceParent)) {
        return ConfigureCopyRootsResult.unsafeOverlap;
      }
    }
    await _repository.saveCopyRoots(
      managedLibraryRoot: managed,
      backupRoot: backup,
    );
    return ConfigureCopyRootsResult.saved;
  }

  bool _overlap(String a, String b) {
    String normalize(String value) => value
        .replaceAll('/', r'\')
        .toLowerCase()
        .replaceFirst(RegExp(r'\\+$'), '');
    final x = normalize(a);
    final y = normalize(b);
    return x == y || x.startsWith('$y\\') || y.startsWith('$x\\');
  }

  String _parent(String path) {
    final normalized = path.replaceAll('/', r'\');
    final separator = normalized.lastIndexOf(r'\');
    return separator <= 2
        ? normalized.substring(0, separator + 1)
        : normalized.substring(0, separator);
  }
}
