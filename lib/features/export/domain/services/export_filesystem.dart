// lib/features/export/domain/services/export_filesystem.dart

/// Filesystem boundary for export-batch generation.
///
/// Implementations live in the data layer and may import dart:io. Domain and
/// application layers depend only on this abstraction.
abstract class ExportFilesystem {
  /// Creates [dirPath] and all missing ancestors. Idempotent.
  Future<ExportFilesystemResult> ensureDirectoryExists(String dirPath);

  /// Copies bytes from [sourcePath] to [destPath]. Never overwrites an
  /// existing [destPath]; returns [ExportFilesystemFailure] when it already
  /// exists.
  Future<ExportFilesystemResult> copyFile(String sourcePath, String destPath);

  /// Copies bytes from [sourcePath] to [destPath], replacing any existing file.
  /// Used when a pool file exists but its hash no longer matches — the managed
  /// copy was re-exported with a newer version.
  Future<ExportFilesystemResult> copyFileReplacing(
    String sourcePath,
    String destPath,
  );

  /// Writes [content] as UTF-8 to [filePath]. Never overwrites an existing
  /// [filePath]; returns [ExportFilesystemFailure] when it already exists.
  Future<ExportFilesystemResult> writeTextFile(String filePath, String content);

  /// Returns the byte size of the file at [path], or null on error.
  Future<int?> fileSize(String path);

  /// Returns true when [path] is an existing regular file.
  bool isExistingFile(String path);
}

/// Result of an [ExportFilesystem] boundary call.
sealed class ExportFilesystemResult {
  const ExportFilesystemResult();
}

final class ExportFilesystemSuccess extends ExportFilesystemResult {
  const ExportFilesystemSuccess();
}

final class ExportFilesystemFailure extends ExportFilesystemResult {
  const ExportFilesystemFailure({required this.safeMessage});

  /// Short, safe English description. Never includes file contents or raw OS
  /// exception messages that could expose user data.
  final String safeMessage;
}
