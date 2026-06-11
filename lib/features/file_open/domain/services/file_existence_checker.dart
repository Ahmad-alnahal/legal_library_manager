// lib/features/file_open/domain/services/file_existence_checker.dart

/// Result of a filesystem existence check on a stored absolute path.
enum FileExistenceStatus {
  /// The path exists and resolves to a regular file.
  regularFile,

  /// The path exists and resolves to a directory.
  directory,

  /// The path does not exist on the filesystem.
  notFound,

  /// The path could not be inspected due to a permission or OS error.
  accessDenied,
}

/// Abstraction for inspecting whether a stored absolute path exists as a
/// regular file.
///
/// Implementations live in the data layer and may use [dart:io]. They must
/// never create, modify, move, rename, or delete the path or any file.
abstract class FileExistenceChecker {
  const FileExistenceChecker();

  /// Synchronously checks [absolutePath] and returns its status.
  FileExistenceStatus checkFile(String absolutePath);
}
