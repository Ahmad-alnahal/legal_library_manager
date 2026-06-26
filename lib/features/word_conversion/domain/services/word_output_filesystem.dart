// lib/features/word_conversion/domain/services/word_output_filesystem.dart

/// Result of a conversion-output filesystem boundary call.
sealed class OutputOperationResult {
  const OutputOperationResult();
}

final class OutputSuccess extends OutputOperationResult {
  const OutputSuccess();
}

final class OutputFailure extends OutputOperationResult {
  const OutputFailure({required this.safeMessage});

  /// Stable English error description — never contains raw OS error text or paths.
  final String safeMessage;
}

/// Filesystem boundary for conversion-output operations.
///
/// Implementations live in the data layer and may import `dart:io`. Domain and
/// application layers depend only on this abstraction. All mutation methods
/// operate exclusively on app-owned output paths inside the designated output
/// directory; no source file or staged-copy path is ever deleted, renamed, or
/// overwritten through this interface.
abstract class WordOutputFilesystem {
  /// Ensures [outputDir] exists as a directory. Creates it only when its
  /// parent already exists; does not create intermediate directories.
  Future<OutputOperationResult> ensureOutputDirectory(String outputDir);

  /// Returns true when [path] refers to an existing regular file.
  bool isExistingFile(String path);

  /// Returns the size in bytes of [path], or null on read error.
  Future<int?> fileSize(String path);

  /// Returns the first [count] bytes of [path], or null on read error.
  Future<List<int>?> readFirstBytes(String path, int count);

  /// Atomically renames [fromPath] to [toPath].
  ///
  /// Returns [OutputFailure] when [toPath] already exists (to avoid silently
  /// overwriting a previously finalized managed file) or on any filesystem
  /// error.
  Future<OutputOperationResult> renameOutputFile(
    String fromPath,
    String toPath,
  );

  /// Deletes [path] when it is directly inside [outputDir].
  ///
  /// Returns [OutputSuccess] whether or not the file existed. Returns
  /// [OutputFailure] for path-safety violations (path outside outputDir).
  Future<OutputOperationResult> deleteOutputFileSafe(
    String path,
    String outputDir,
  );
}
