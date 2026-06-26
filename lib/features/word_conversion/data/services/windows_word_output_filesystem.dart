// lib/features/word_conversion/data/services/windows_word_output_filesystem.dart

import 'dart:io';

import '../../domain/services/word_output_filesystem.dart';

/// Windows filesystem implementation of [WordOutputFilesystem].
///
/// All mutation methods are guarded so they can only act on paths inside the
/// designated output directory. No source file or staged-copy path is ever
/// deleted, renamed, or overwritten through this class.
class WindowsWordOutputFilesystem implements WordOutputFilesystem {
  const WindowsWordOutputFilesystem();

  @override
  Future<OutputOperationResult> ensureOutputDirectory(String outputDir) async {
    try {
      final dir = Directory(outputDir);
      if (!dir.existsSync()) {
        await dir.create(recursive: false);
      }
      return const OutputSuccess();
    } on FileSystemException {
      return const OutputFailure(
        safeMessage: 'output directory creation failed',
      );
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
  Future<int?> fileSize(String path) async {
    try {
      return File(path).lengthSync();
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<List<int>?> readFirstBytes(String path, int count) async {
    RandomAccessFile? raf;
    try {
      raf = await File(path).open();
      return await raf.read(count);
    } on FileSystemException {
      return null;
    } finally {
      await raf?.close();
    }
  }

  @override
  Future<OutputOperationResult> renameOutputFile(
    String fromPath,
    String toPath,
  ) async {
    try {
      if (File(toPath).existsSync()) {
        return const OutputFailure(
          safeMessage: 'output file target already exists',
        );
      }
      await File(fromPath).rename(toPath);
      return const OutputSuccess();
    } on FileSystemException {
      return const OutputFailure(safeMessage: 'output file rename failed');
    }
  }

  @override
  Future<OutputOperationResult> deleteOutputFileSafe(
    String path,
    String outputDir,
  ) async {
    final normalizedPath = path.replaceAll('/', r'\').toLowerCase();
    final normalizedDir = outputDir.replaceAll('/', r'\').toLowerCase();
    final dirPrefix = normalizedDir.endsWith(r'\')
        ? normalizedDir
        : '$normalizedDir\\';
    if (!normalizedPath.startsWith(dirPrefix)) {
      return const OutputFailure(
        safeMessage: 'path is outside the output directory',
      );
    }
    try {
      final file = File(path);
      if (file.existsSync()) {
        await file.delete();
      }
      return const OutputSuccess();
    } on FileSystemException {
      return const OutputFailure(safeMessage: 'output file deletion failed');
    }
  }
}
