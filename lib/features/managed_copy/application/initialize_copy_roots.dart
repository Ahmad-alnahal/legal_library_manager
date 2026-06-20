import '../domain/entities/copy_roots_setup_report.dart';
import '../domain/repositories/managed_copy_repository.dart';
import '../domain/services/documents_directory_resolver.dart';
import '../domain/services/managed_library_filesystem.dart';
import 'configure_copy_roots.dart';

/// Automatically configures safe default copy roots on startup (M8.4).
///
/// Defaults live under the user's Documents directory:
/// `<Documents>\MARJIY\ManagedLibrary` and `<Documents>\MARJIY\DatabaseBackups`.
///
/// Safety rules:
/// - Never overwrites an already configured root; only missing configuration
///   is filled, and only after passing the same canonical-path and overlap
///   validation used by manual configuration ([ConfigureCopyRoots]).
/// - Recreates a missing directory only when it is the MARJIY default
///   location; missing custom directories require user attention instead.
/// - Directory creation is idempotent and never touches existing contents.
///   No file is ever copied, moved, renamed, deleted, or overwritten here.
/// - Never throws: every failure (Documents unresolvable, creation failure,
///   validation failure, persistence error) is reported as a typed
///   [CopyRootsSetupOutcome.requiresAttention] result.
class InitializeCopyRoots {
  const InitializeCopyRoots({
    required this._repository,
    required this._filesystem,
    required this._documentsResolver,
    required this._configureCopyRoots,
  });

  final ManagedCopyRepository _repository;
  final ManagedLibraryFilesystem _filesystem;
  final DocumentsDirectoryResolver _documentsResolver;
  final ConfigureCopyRoots _configureCopyRoots;

  static const String marjiyFolderName = 'MARJIY';
  static const String managedLibraryFolderName = 'ManagedLibrary';
  static const String databaseBackupsFolderName = 'DatabaseBackups';

  Future<CopyRootsSetupReport> call() async {
    try {
      return await _run();
    } catch (_) {
      // Startup must never crash on initialization problems; the typed
      // attention outcome keeps managed-copy actions safely blocked.
      return const CopyRootsSetupReport(
        outcome: CopyRootsSetupOutcome.requiresAttention,
      );
    }
  }

  Future<CopyRootsSetupReport> _run() async {
    final roots = await _repository.loadCopyRoots();
    final managed = roots.managedLibraryRoot;
    final backup = roots.backupRoot;
    final defaults = _defaultsFor(
      await _documentsResolver.resolveDocumentsPath(),
    );

    if (managed != null && backup != null) {
      return _describeConfigured(managed, backup, defaults);
    }
    if (managed == null && backup == null) {
      return _configureBothDefaults(defaults);
    }
    return _fillMissingRoot(managed, backup, defaults);
  }

  // ── Both roots configured: describe, recreating missing defaults only ─────

  Future<CopyRootsSetupReport> _describeConfigured(
    String managed,
    String backup,
    _DefaultRoots? defaults,
  ) async {
    final managedResult = await _statusOf(
      managed,
      defaults,
      defaults?.managedLibrary,
    );
    final backupResult = await _statusOf(
      backup,
      defaults,
      defaults?.databaseBackups,
    );
    final bool healthy =
        managedResult.status != CopyRootStatus.missing &&
        backupResult.status != CopyRootStatus.missing;
    final CopyRootsSetupOutcome outcome = !healthy
        ? CopyRootsSetupOutcome.requiresAttention
        : (managedResult.recreated || backupResult.recreated)
        ? CopyRootsSetupOutcome.defaultRecreated
        : CopyRootsSetupOutcome.alreadyConfigured;
    return CopyRootsSetupReport(
      outcome: outcome,
      managedRoot: managed,
      backupRoot: backup,
      managedStatus: managedResult.status,
      backupStatus: backupResult.status,
    );
  }

  // ── Neither root configured: create and persist both defaults ─────────────

  Future<CopyRootsSetupReport> _configureBothDefaults(
    _DefaultRoots? defaults,
  ) async {
    if (defaults == null ||
        !await _ensureDefaultDirectory(defaults, defaults.managedLibrary) ||
        !await _ensureDefaultDirectory(defaults, defaults.databaseBackups)) {
      return const CopyRootsSetupReport(
        outcome: CopyRootsSetupOutcome.requiresAttention,
      );
    }
    final result = await _configureCopyRoots(
      defaults.managedLibrary,
      defaults.databaseBackups,
    );
    if (result != ConfigureCopyRootsResult.saved) {
      return const CopyRootsSetupReport(
        outcome: CopyRootsSetupOutcome.requiresAttention,
      );
    }
    return CopyRootsSetupReport(
      outcome: CopyRootsSetupOutcome.defaultsCreated,
      managedRoot: defaults.managedLibrary,
      backupRoot: defaults.databaseBackups,
      managedStatus: CopyRootStatus.automatic,
      backupStatus: CopyRootStatus.automatic,
    );
  }

  // ── Exactly one root configured: fill only the missing root ───────────────

  Future<CopyRootsSetupReport> _fillMissingRoot(
    String? managed,
    String? backup,
    _DefaultRoots? defaults,
  ) async {
    final bool fillingManaged = managed == null;
    final String existing = fillingManaged ? backup! : managed;

    CopyRootsSetupReport attention(CopyRootStatus existingStatus) =>
        CopyRootsSetupReport(
          outcome: CopyRootsSetupOutcome.requiresAttention,
          managedRoot: managed,
          backupRoot: backup,
          managedStatus: fillingManaged
              ? CopyRootStatus.notConfigured
              : existingStatus,
          backupStatus: fillingManaged
              ? existingStatus
              : CopyRootStatus.notConfigured,
        );

    final existingResult = await _statusOf(
      existing,
      defaults,
      fillingManaged ? defaults?.databaseBackups : defaults?.managedLibrary,
    );
    if (defaults == null || existingResult.status == CopyRootStatus.missing) {
      return attention(existingResult.status);
    }

    final String fillPath = fillingManaged
        ? defaults.managedLibrary
        : defaults.databaseBackups;
    if (!await _ensureDefaultDirectory(defaults, fillPath)) {
      return attention(existingResult.status);
    }
    // Re-persisting the existing root with its unchanged value is not a
    // replacement; only the missing root receives a new (default) value.
    final result = await _configureCopyRoots(
      fillingManaged ? fillPath : managed,
      fillingManaged ? backup : fillPath,
    );
    if (result != ConfigureCopyRootsResult.saved) {
      return attention(existingResult.status);
    }
    return CopyRootsSetupReport(
      outcome: CopyRootsSetupOutcome.missingRootFilled,
      managedRoot: fillingManaged ? fillPath : managed,
      backupRoot: fillingManaged ? backup : fillPath,
      managedStatus: fillingManaged
          ? CopyRootStatus.automatic
          : existingResult.status,
      backupStatus: fillingManaged
          ? existingResult.status
          : CopyRootStatus.automatic,
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// Status of an already configured root. A missing directory is recreated
  /// only when it is exactly the MARJIY default location.
  Future<({CopyRootStatus status, bool recreated})> _statusOf(
    String configured,
    _DefaultRoots? defaults,
    String? defaultPath,
  ) async {
    final bool isDefault =
        defaultPath != null && _samePath(configured, defaultPath);
    if (_filesystem.isExistingDirectory(configured)) {
      return (
        status: isDefault ? CopyRootStatus.automatic : CopyRootStatus.custom,
        recreated: false,
      );
    }
    if (isDefault && defaults != null) {
      if (await _ensureDefaultDirectory(defaults, defaultPath)) {
        return (status: CopyRootStatus.automatic, recreated: true);
      }
    }
    return (status: CopyRootStatus.missing, recreated: false);
  }

  /// Idempotently creates `<Documents>\MARJIY` and then [rootPath] beneath
  /// it. Existing directories and their contents are never modified.
  Future<bool> _ensureDefaultDirectory(
    _DefaultRoots defaults,
    String rootPath,
  ) async {
    final parent = await _filesystem.ensureDirectoryExists(defaults.marjiy);
    if (parent is! FilesystemSuccess) return false;
    final root = await _filesystem.ensureDirectoryExists(rootPath);
    if (root is! FilesystemSuccess) return false;
    return _filesystem.isExistingDirectory(rootPath);
  }

  _DefaultRoots? _defaultsFor(String? documentsPath) {
    if (documentsPath == null) return null;
    final trimmed = documentsPath
        .replaceAll('/', r'\')
        .replaceFirst(RegExp(r'\\+$'), '');
    if (trimmed.isEmpty) return null;
    final marjiy = '$trimmed\\$marjiyFolderName';
    return _DefaultRoots(
      marjiy: marjiy,
      managedLibrary: '$marjiy\\$managedLibraryFolderName',
      databaseBackups: '$marjiy\\$databaseBackupsFolderName',
    );
  }

  bool _samePath(String a, String b) {
    String normalize(String value) => value
        .replaceAll('/', r'\')
        .toLowerCase()
        .replaceFirst(RegExp(r'\\+$'), '');
    return normalize(a) == normalize(b);
  }
}

class _DefaultRoots {
  const _DefaultRoots({
    required this.marjiy,
    required this.managedLibrary,
    required this.databaseBackups,
  });

  final String marjiy;
  final String managedLibrary;
  final String databaseBackups;
}
