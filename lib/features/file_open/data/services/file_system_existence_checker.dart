// lib/features/file_open/data/services/file_system_existence_checker.dart

import 'dart:io';

import '../../domain/services/file_existence_checker.dart';

/// [dart:io]-backed [FileExistenceChecker].
///
/// Never creates, modifies, moves, renames, or deletes any file or directory.
/// Read-only.
class FileSystemExistenceChecker implements FileExistenceChecker {
  const FileSystemExistenceChecker();

  @override
  FileExistenceStatus checkFile(String absolutePath) {
    try {
      final FileSystemEntityType type = FileSystemEntity.typeSync(
        absolutePath,
        followLinks: true,
      );
      return switch (type) {
        FileSystemEntityType.file => FileExistenceStatus.regularFile,
        FileSystemEntityType.directory => FileExistenceStatus.directory,
        _ => FileExistenceStatus.notFound,
      };
    } on FileSystemException {
      return FileExistenceStatus.accessDenied;
    }
  }
}
