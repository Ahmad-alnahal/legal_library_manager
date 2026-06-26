// lib/features/word_conversion/domain/services/word_staging_filesystem.dart

/// Result of a staging filesystem boundary call.
sealed class StagingOperationResult {
  const StagingOperationResult();
}

final class StagingSuccess extends StagingOperationResult {
  const StagingSuccess();
}

final class StagingFailure extends StagingOperationResult {
  const StagingFailure({required this.safeMessage});

  /// Stable English error description — never contains raw OS error text or paths.
  final String safeMessage;
}

/// Filesystem boundary for Word staging operations.
///
/// Implementations live in the data layer and may import `dart:io`. Domain and
/// application layers depend only on this abstraction. No source file mutation
/// (write, rename, overwrite, delete of a source path) is exposed through this
/// interface. All mutation methods operate exclusively on app-owned staging paths.
abstract class WordStagingFilesystem {
  /// Ensures [stagingDir] exists as a directory. Creates it only when its
  /// parent already exists; does not create intermediate directories.
  ///
  /// Returns [StagingSuccess] when the directory already exists or was created.
  /// Returns [StagingFailure] on filesystem error.
  Future<StagingOperationResult> ensureStagingDirectory(String stagingDir);

  /// Copies bytes from [sourcePath] to [tempDestPath].
  ///
  /// Uses exclusive creation: returns [StagingFailure] when [tempDestPath]
  /// already exists, preventing accidental overwrites.
  Future<StagingOperationResult> copyToTemp(
    String sourcePath,
    String tempDestPath,
  );

  /// Renames [tempPath] to [finalPath].
  ///
  /// Returns [StagingSuccess] immediately when [finalPath] already exists
  /// (content-addressed idempotency). Returns [StagingFailure] on rename
  /// failure.
  Future<StagingOperationResult> finalize(String tempPath, String finalPath);

  /// Deletes [tempPath] when it is directly inside [stagingDir] and ends with
  /// the `.staging` suffix.
  ///
  /// Returns [StagingSuccess] whether or not the file existed. Returns
  /// [StagingFailure] for path-safety violations (wrong parent dir or missing
  /// suffix), which indicate a bug in the caller — the original is never
  /// touched regardless.
  Future<StagingOperationResult> deleteTempSafe(
    String tempPath,
    String stagingDir,
  );

  /// Returns true when [path] refers to an existing regular file.
  bool isExistingFile(String path);

  /// Deletes a finalized staged file at [path] when it is directly inside
  /// [stagingDir].
  ///
  /// Unlike [deleteTempSafe], no suffix constraint is applied — this is for
  /// removing the finalized staged copy (e.g. `<hash>.doc`) after a successful
  /// conversion. Returns [StagingSuccess] whether or not the file existed.
  /// Returns [StagingFailure] for path-safety violations or OS errors.
  Future<StagingOperationResult> deleteStagedFileSafe(
    String path,
    String stagingDir,
  );
}
