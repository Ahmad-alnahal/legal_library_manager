// lib/features/managed_copy/data/services/windows_managed_library_filesystem.dart

import 'dart:io';

import '../../domain/services/managed_library_filesystem.dart';

/// dart:io-backed [ManagedLibraryFilesystem] for Windows.
///
/// Only manages app-owned paths inside the managed-library root. Never reads,
/// deletes, renames, or overwrites source file paths. The [copyFile] method
/// reads the source bytes using File.copy (read-only access to the source) and
/// writes them to an app-owned temporary destination. The [finalizeFile] method
/// renames only the app-owned temporary path to the final managed path; no
/// source path is ever passed to rename/delete operations.
///
/// All [FilesystemFailure] messages are stable, safe English codes. Raw OS
/// error messages, exception text, and filesystem paths are never embedded in
/// result values.
class WindowsManagedLibraryFilesystem implements ManagedLibraryFilesystem {
  const WindowsManagedLibraryFilesystem();

  @override
  bool isExistingDirectory(String path) {
    try {
      return Directory(path).existsSync();
    } on FileSystemException {
      return false;
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
  Future<FilesystemOperationResult> ensureDirectoryExists(
    String absoluteDirPath,
  ) async {
    try {
      final dir = Directory(absoluteDirPath);
      if (!dir.existsSync()) {
        await dir.create(recursive: false);
      }
      return const FilesystemSuccess();
    } on FileSystemException {
      return const FilesystemFailure(safeMessage: 'Directory creation failed.');
    }
  }

  @override
  Future<FilesystemOperationResult> copyFile(
    String sourcePath,
    String destPath,
  ) async {
    try {
      // Exclusive creation makes the no-overwrite decision atomic. A separate
      // exists-check followed by File.copy would leave a race where another
      // operation could create the destination between those two calls.
      await File(destPath).create(exclusive: true);
      await File(
        sourcePath,
      ).openRead().pipe(File(destPath).openWrite(mode: FileMode.writeOnly));
      return const FilesystemSuccess();
    } on FileSystemException {
      return const FilesystemFailure(safeMessage: 'File copy failed.');
    }
  }

  @override
  Future<FilesystemOperationResult> finalizeFile(
    String tmpPath,
    String finalPath,
  ) async {
    try {
      if (File(finalPath).existsSync()) {
        return const FilesystemFailure(
          safeMessage: 'Final target already exists.',
        );
      }
      await File(tmpPath).rename(finalPath);
      return const FilesystemSuccess();
    } on FileSystemException {
      return const FilesystemFailure(safeMessage: 'File rename failed.');
    }
  }

  @override
  Future<FilesystemOperationResult> deleteFile(String path) async {
    try {
      await File(path).delete();
      return const FilesystemSuccess();
    } on FileSystemException {
      return const FilesystemFailure(safeMessage: 'File deletion failed.');
    }
  }

  @override
  Future<int?> fileSize(String path) async {
    try {
      return await File(path).length();
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<List<String>?> findRecoveryArtifacts(
    String managedFilesDir,
    String documentCode,
  ) async {
    try {
      final dir = Directory(managedFilesDir);
      if (!dir.existsSync()) return const [];
      final escaped = RegExp.escape(documentCode);
      // Only match in-progress temporary files (.copying suffix required).
      // The final managed copy (<code>.pdf) is handled by the explicit
      // isExistingFile(finalPath) checks in the use case and must NOT be
      // returned here, as it is not an artifact of an interrupted operation.
      final ownedName = RegExp('^$escaped\\.pdf\\.[A-Za-z0-9_-]+\\.copying\$');
      final artifacts = <String>[];
      for (final entity in dir.listSync(followLinks: false)) {
        if (FileSystemEntity.typeSync(entity.path, followLinks: false) !=
            FileSystemEntityType.file) {
          continue;
        }
        final name = entity.uri.pathSegments.isEmpty
            ? ''
            : entity.uri.pathSegments.last;
        if (ownedName.hasMatch(name)) artifacts.add(entity.path);
      }
      artifacts.sort();
      return artifacts;
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<FilesystemOperationResult> deleteRecoveryArtifact(
    String path,
    String allowedRoot,
  ) async {
    try {
      if (path.trim().isEmpty || allowedRoot.trim().isEmpty) {
        return const FilesystemFailure(safeMessage: 'Empty path or root.');
      }
      final normPath = path.replaceAll('/', r'\');
      final normRoot = allowedRoot.replaceAll('/', r'\');
      final rootWithSep = normRoot.endsWith(r'\') ? normRoot : '$normRoot\\';
      if (!normPath.toLowerCase().startsWith(rootWithSep.toLowerCase())) {
        return const FilesystemFailure(
          safeMessage: 'Path is outside allowed root.',
        );
      }
      final remainder = normPath.substring(rootWithSep.length);
      if (remainder.isEmpty || remainder.contains(r'\')) {
        return const FilesystemFailure(
          safeMessage: 'Path is nested or invalid.',
        );
      }
      final type = FileSystemEntity.typeSync(path, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        return const FilesystemSuccess();
      }
      if (type != FileSystemEntityType.file) {
        return const FilesystemFailure(
          safeMessage: 'Target is not a regular file.',
        );
      }
      await File(path).delete();
      return const FilesystemSuccess();
    } on FileSystemException {
      return const FilesystemFailure(
        safeMessage: 'Recovery artifact deletion failed.',
      );
    }
  }

  @override
  Future<List<String>?> findStartupRecoveryArtifacts(
    String managedFilesDir,
    List<String> documentCodes,
  ) async {
    try {
      final dir = Directory(managedFilesDir);
      if (!dir.existsSync()) return const [];
      final knownCodes = documentCodes.toSet();
      final copyingName = RegExp(
        r'^(DOC-[0-9]{7})\.pdf\.[A-Za-z0-9_-]+\.copying$',
      );
      final finalName = RegExp(r'^(DOC-[0-9]{7})\.pdf$');
      final artifacts = <String>[];
      for (final entity in dir.listSync(followLinks: false)) {
        if (FileSystemEntity.typeSync(entity.path, followLinks: false) !=
            FileSystemEntityType.file) {
          continue;
        }
        final name = entity.uri.pathSegments.isEmpty
            ? ''
            : entity.uri.pathSegments.last;
        final copyingMatch = copyingName.firstMatch(name);
        if (copyingMatch != null) {
          artifacts.add(entity.path);
          continue;
        }
        final finalMatch = finalName.firstMatch(name);
        final code = finalMatch?.group(1);
        if (code != null && !knownCodes.contains(code)) {
          artifacts.add(entity.path);
        }
      }
      artifacts.sort();
      return artifacts;
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<List<String>?> findStartupBackupArtifacts(String backupRoot) async {
    try {
      final dir = Directory(backupRoot);
      if (!dir.existsSync()) return const [];
      final backupName = RegExp(
        r'^legal_library_backup_[0-9]{4}-[0-9]{2}-[0-9]{2}_'
        r'[0-9]{6}_[A-Za-z0-9_-]+\.sqlite$',
      );
      final artifacts = <String>[];
      for (final entity in dir.listSync(followLinks: false)) {
        if (FileSystemEntity.typeSync(entity.path, followLinks: false) !=
            FileSystemEntityType.file) {
          continue;
        }
        final name = entity.uri.pathSegments.isEmpty
            ? ''
            : entity.uri.pathSegments.last;
        if (!backupName.hasMatch(name)) continue;
        final size = await fileSize(entity.path);
        if (size == null || size < 100) {
          artifacts.add(entity.path);
        }
      }
      artifacts.sort();
      return artifacts;
    } on FileSystemException {
      return null;
    }
  }
}
