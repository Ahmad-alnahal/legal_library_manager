// lib/features/managed_copy/domain/services/managed_library_filesystem.dart

/// Filesystem boundary for managed-copy operations.
///
/// Implementations live in the data layer and may import dart:io. Domain and
/// application layers depend only on this abstraction. No source-file mutation
/// (delete, rename, overwrite) is exposed through this interface.
abstract class ManagedLibraryFilesystem {
  /// Returns true when [path] is an absolute directory that currently exists.
  bool isExistingDirectory(String path);

  /// Returns true when [path] is an existing regular file (not a directory).
  bool isExistingFile(String path);

  /// Ensures [absoluteDirPath] exists as a directory, creating it only when
  /// its parent already exists.
  Future<FilesystemOperationResult> ensureDirectoryExists(
    String absoluteDirPath,
  );

  /// Copies bytes from [sourcePath] to [destPath]. Never overwrites an
  /// existing [destPath]; returns [FilesystemFailure] when it already exists.
  Future<FilesystemOperationResult> copyFile(
    String sourcePath,
    String destPath,
  );

  /// Atomically renames [tmpPath] to [finalPath]. Never overwrites an existing
  /// [finalPath]; returns [FilesystemFailure] when it already exists.
  Future<FilesystemOperationResult> finalizeFile(
    String tmpPath,
    String finalPath,
  );

  /// Returns the size in bytes of the file at [path], or null on error.
  Future<int?> fileSize(String path);

  /// Finds strict MARJIY-owned artifacts for [documentCode] directly inside
  /// [managedFilesDir] without recursing, following links, or modifying files.
  /// Returns null when the directory cannot be inspected safely.
  ///
  /// Only returns in-progress temporary files (`.copying` suffix). The final
  /// managed copy (`<code>.pdf`) is handled separately by the use case and is
  /// NOT included in the result.
  Future<List<String>?> findRecoveryArtifacts(
    String managedFilesDir,
    String documentCode,
  );

  /// Deletes the file at [path]. Used only on app-owned managed-library paths
  /// (never on source files) to remove a conflicting or unverifiable managed
  /// copy before writing a fresh, verified copy.
  ///
  /// A pre-copy database backup MUST exist before this is called.
  Future<FilesystemOperationResult> deleteFile(String path);
}

/// Result of a filesystem boundary call.
sealed class FilesystemOperationResult {
  const FilesystemOperationResult();
}

final class FilesystemSuccess extends FilesystemOperationResult {
  const FilesystemSuccess();
}

final class FilesystemFailure extends FilesystemOperationResult {
  const FilesystemFailure({required this.safeMessage});

  /// Short, safe English description. Must not include file contents or raw
  /// OS exception messages that could expose user data.
  final String safeMessage;
}
