// lib/features/managed_copy/application/apply_default_copy_roots.dart

import '../../security/application/session_manager.dart';
import '../../security/domain/entities/account_role.dart';
import '../domain/services/documents_directory_resolver.dart';
import '../domain/services/managed_library_filesystem.dart';
import 'configure_copy_roots.dart';

/// Outcome of resetting both copy roots to the real MARJIY defaults (M8.6 Part A).
enum ApplyDefaultCopyRootsResult {
  /// Both default directories were created or already existed, validated, and
  /// persisted as the new roots.
  applied,

  /// The user's Documents directory could not be resolved.
  documentsNotResolvable,

  /// At least one default directory could not be created.
  directoryCreationFailed,

  /// The default paths would overlap with each other, the database root, or a
  /// registered source folder.
  unsafeOverlap,

  /// [ConfigureCopyRoots] returned an unexpected error (invalid folder, etc.).
  configurationFailed,

  /// Caller does not hold an active administrator session.
  unauthorized,
}

/// Forces both configured roots to the canonical MARJIY default locations
/// (Part A of M8.6).
///
/// Unlike [InitializeCopyRoots] (which only fills missing roots), this use case
/// always computes, creates, and persists both defaults — even when custom roots
/// are already configured. Existing managed files and backups at the old
/// locations are never moved, renamed, deleted, or overwritten.
///
/// Default locations:
///   `<Documents>\MARJIY\ManagedLibrary`
///   `<Documents>\MARJIY\DatabaseBackups`
///
/// No dart:io, Drift, or path_provider imports are permitted here.
class ApplyDefaultCopyRoots {
  const ApplyDefaultCopyRoots({
    required this._documentsResolver,
    required this._filesystem,
    required this._configureCopyRoots,
    required this._sessionManager,
  });

  final DocumentsDirectoryResolver _documentsResolver;
  final ManagedLibraryFilesystem _filesystem;
  final ConfigureCopyRoots _configureCopyRoots;
  final SessionManager _sessionManager;

  static const String _marjiyFolder = 'MARJIY';
  static const String _managedLibraryFolder = 'ManagedLibrary';
  static const String _databaseBackupsFolder = 'DatabaseBackups';

  Future<ApplyDefaultCopyRootsResult> call() async {
    final session = _sessionManager.currentSession;
    if (session == null || session.role != AccountRole.admin) {
      return ApplyDefaultCopyRootsResult.unauthorized;
    }

    final String? documentsPath = await _documentsResolver
        .resolveDocumentsPath();
    if (documentsPath == null) {
      return ApplyDefaultCopyRootsResult.documentsNotResolvable;
    }

    final String trimmed = documentsPath
        .replaceAll('/', r'\')
        .replaceFirst(RegExp(r'\\+$'), '');
    if (trimmed.isEmpty) {
      return ApplyDefaultCopyRootsResult.documentsNotResolvable;
    }

    final String marjiy = '$trimmed\\$_marjiyFolder';
    final String managedRoot = '$marjiy\\$_managedLibraryFolder';
    final String backupRoot = '$marjiy\\$_databaseBackupsFolder';

    // Create <Documents>\MARJIY if needed, then the two leaf directories.
    final marjiyResult = await _filesystem.ensureDirectoryExists(marjiy);
    if (marjiyResult is FilesystemFailure) {
      return ApplyDefaultCopyRootsResult.directoryCreationFailed;
    }
    final managedResult = await _filesystem.ensureDirectoryExists(managedRoot);
    if (managedResult is FilesystemFailure) {
      return ApplyDefaultCopyRootsResult.directoryCreationFailed;
    }
    final backupResult = await _filesystem.ensureDirectoryExists(backupRoot);
    if (backupResult is FilesystemFailure) {
      return ApplyDefaultCopyRootsResult.directoryCreationFailed;
    }

    // Delegate all safety validation (overlaps, sources, database-root) and
    // transactional persistence to the existing ConfigureCopyRoots use case.
    final result = await _configureCopyRoots(managedRoot, backupRoot);
    return switch (result) {
      ConfigureCopyRootsResult.saved => ApplyDefaultCopyRootsResult.applied,
      ConfigureCopyRootsResult.unsafeOverlap =>
        ApplyDefaultCopyRootsResult.unsafeOverlap,
      ConfigureCopyRootsResult.unauthorized =>
        ApplyDefaultCopyRootsResult.unauthorized,
      _ => ApplyDefaultCopyRootsResult.configurationFailed,
    };
  }
}
