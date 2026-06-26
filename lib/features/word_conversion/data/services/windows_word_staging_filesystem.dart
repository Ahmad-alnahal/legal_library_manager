// lib/features/word_conversion/data/services/windows_word_staging_filesystem.dart

import 'dart:io';

import '../../domain/services/word_staging_filesystem.dart';

/// dart:io-backed [WordStagingFilesystem] for Windows.
///
/// Only manages app-owned paths inside the Word staging directory. The
/// [copyToTemp] method opens the source file read-only (via [File.openRead])
/// and writes bytes to an app-owned temporary destination; the source is never
/// opened for writing. [finalize] renames only the app-owned temp path. No
/// source file path is ever passed to rename, delete, or write operations.
///
/// All [StagingFailure] messages are stable, safe English codes. Raw OS error
/// messages, exception text, and filesystem paths are never embedded in result
/// values.
class WindowsWordStagingFilesystem implements WordStagingFilesystem {
  const WindowsWordStagingFilesystem();

  @override
  Future<StagingOperationResult> ensureStagingDirectory(
    String stagingDir,
  ) async {
    try {
      final dir = Directory(stagingDir);
      if (!dir.existsSync()) {
        await dir.create(recursive: false);
      }
      return const StagingSuccess();
    } on FileSystemException {
      return const StagingFailure(
        safeMessage: 'staging directory creation failed',
      );
    }
  }

  @override
  Future<StagingOperationResult> copyToTemp(
    String sourcePath,
    String tempDestPath,
  ) async {
    try {
      // Exclusive creation makes the no-overwrite decision atomic.
      await File(tempDestPath).create(exclusive: true);
      await File(
        sourcePath,
      ).openRead().pipe(File(tempDestPath).openWrite(mode: FileMode.writeOnly));
      return const StagingSuccess();
    } on FileSystemException {
      return const StagingFailure(safeMessage: 'temp file copy failed');
    }
  }

  @override
  Future<StagingOperationResult> finalize(
    String tempPath,
    String finalPath,
  ) async {
    try {
      // Content-addressed: if the final path already exists it must be the same
      // file, so completing the rename is unnecessary.
      if (File(finalPath).existsSync()) {
        return const StagingSuccess();
      }
      await File(tempPath).rename(finalPath);
      return const StagingSuccess();
    } on FileSystemException {
      return const StagingFailure(safeMessage: 'staging finalization failed');
    }
  }

  @override
  Future<StagingOperationResult> deleteTempSafe(
    String tempPath,
    String stagingDir,
  ) async {
    // Safety guards: the temp path must be directly inside the staging dir and
    // must carry the .staging sentinel suffix.
    final String normalizedTemp = tempPath.replaceAll('/', r'\').toLowerCase();
    final String normalizedDir = stagingDir.replaceAll('/', r'\').toLowerCase();
    final String dirPrefix = normalizedDir.endsWith(r'\')
        ? normalizedDir
        : '$normalizedDir\\';

    if (!normalizedTemp.startsWith(dirPrefix)) {
      return const StagingFailure(
        safeMessage: 'temp path is outside the staging directory',
      );
    }
    if (!tempPath.endsWith('.staging')) {
      return const StagingFailure(
        safeMessage: 'temp path does not carry the .staging suffix',
      );
    }

    try {
      final file = File(tempPath);
      if (file.existsSync()) {
        await file.delete();
      }
      return const StagingSuccess();
    } on FileSystemException {
      return const StagingFailure(safeMessage: 'temp file deletion failed');
    }
  }

  @override
  bool isExistingFile(String path) {
    try {
      return File(path).existsSync();
    } on FileSystemException {
      return false;
    }
  }

  @override
  Future<StagingOperationResult> deleteStagedFileSafe(
    String path,
    String stagingDir,
  ) async {
    final String normalizedPath = path.replaceAll('/', r'\').toLowerCase();
    final String normalizedDir = stagingDir.replaceAll('/', r'\').toLowerCase();
    final String dirPrefix = normalizedDir.endsWith(r'\')
        ? normalizedDir
        : '$normalizedDir\\';

    if (!normalizedPath.startsWith(dirPrefix)) {
      return const StagingFailure(
        safeMessage: 'staged file path is outside the staging directory',
      );
    }
    // No subdirectory nesting allowed — the file must be directly in stagingDir.
    final remainder = normalizedPath.substring(dirPrefix.length);
    if (remainder.contains(r'\')) {
      return const StagingFailure(
        safeMessage: 'staged file path is nested inside a subdirectory',
      );
    }

    try {
      final file = File(path);
      if (file.existsSync()) {
        await file.delete();
      }
      return const StagingSuccess();
    } on FileSystemException {
      return const StagingFailure(safeMessage: 'staged file deletion failed');
    }
  }
}
