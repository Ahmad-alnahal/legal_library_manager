// lib/features/export/data/services/windows_export_filesystem.dart

import 'dart:convert';
import 'dart:io';

import '../../domain/services/export_filesystem.dart';

/// dart:io-backed [ExportFilesystem] for Windows.
///
/// All [ExportFilesystemFailure] messages are stable, safe English codes. Raw
/// OS error messages, exception text, and filesystem paths are never embedded
/// in result values.
class WindowsExportFilesystem implements ExportFilesystem {
  const WindowsExportFilesystem();

  @override
  Future<ExportFilesystemResult> ensureDirectoryExists(String dirPath) async {
    try {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
      return const ExportFilesystemSuccess();
    } on FileSystemException {
      return const ExportFilesystemFailure(
        safeMessage: 'Directory creation failed.',
      );
    }
  }

  @override
  Future<ExportFilesystemResult> copyFile(
    String sourcePath,
    String destPath,
  ) async {
    try {
      // Exclusive creation makes the no-overwrite decision atomic. A separate
      // exists-check followed by a copy would leave a race where another
      // operation could create the destination between those two calls.
      await File(destPath).create(exclusive: true);
      await File(
        sourcePath,
      ).openRead().pipe(File(destPath).openWrite(mode: FileMode.writeOnly));
      return const ExportFilesystemSuccess();
    } on FileSystemException {
      return const ExportFilesystemFailure(safeMessage: 'File copy failed.');
    }
  }

  @override
  Future<ExportFilesystemResult> writeTextFile(
    String filePath,
    String content,
  ) async {
    try {
      // Exclusive creation makes the no-overwrite decision atomic, matching
      // copyFile's approach.
      final file = await File(filePath).create(exclusive: true);
      await file.writeAsString(content, encoding: utf8, flush: true);
      return const ExportFilesystemSuccess();
    } on FileSystemException {
      return const ExportFilesystemFailure(safeMessage: 'File write failed.');
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
  bool isExistingFile(String path) {
    try {
      return File(path).existsSync();
    } on FileSystemException {
      return false;
    }
  }
}
