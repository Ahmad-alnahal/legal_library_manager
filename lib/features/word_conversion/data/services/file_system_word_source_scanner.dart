// lib/features/word_conversion/data/services/file_system_word_source_scanner.dart

import 'dart:io';

import '../../domain/entities/word_source_file.dart';
import '../../domain/services/word_source_scanner.dart';

/// dart:io-backed [WordSourceScanner].
///
/// Scans a folder for `.doc` files. Extension matching is
/// case-insensitive. Symbolic links are never followed. Scan failures for
/// individual entries are collected as [WordScanFailure] values so the overall
/// scan continues. Results are sorted lexicographically by path for
/// deterministic output.
///
/// No source file is opened for writing. No file is renamed, deleted, or
/// overwritten at any point during the scan.
class FileSystemWordSourceScanner implements WordSourceScanner {
  const FileSystemWordSourceScanner();

  @override
  Future<WordScanResult> scan(
    String sourceFolder, {
    required bool recursive,
    List<String> protectedPaths = const [],
  }) async {
    final files = <WordSourceFile>[];
    final failures = <WordScanFailure>[];
    final protectedLower = protectedPaths.map((p) => p.toLowerCase()).toSet();

    final dir = Directory(sourceFolder);
    if (!dir.existsSync()) {
      return const WordScanResult(files: []);
    }

    await _scanDirectory(dir, files, failures, protectedLower, recursive);

    files.sort(
      (a, b) =>
          a.absolutePath.toLowerCase().compareTo(b.absolutePath.toLowerCase()),
    );

    return WordScanResult(files: files, failures: failures);
  }

  Future<void> _scanDirectory(
    Directory dir,
    List<WordSourceFile> files,
    List<WordScanFailure> failures,
    Set<String> protectedLower,
    bool recursive,
  ) async {
    List<FileSystemEntity> entries;
    try {
      entries = dir.listSync(recursive: false, followLinks: false);
    } on FileSystemException catch (e) {
      failures.add(
        WordScanFailure(path: dir.path, message: e.osError?.message),
      );
      return;
    }

    for (final entity in entries) {
      if (entity is File) {
        _tryAddFile(entity, files, failures);
      } else if (entity is Directory && recursive) {
        if (protectedLower.contains(entity.path.toLowerCase())) continue;
        await _scanDirectory(
          entity,
          files,
          failures,
          protectedLower,
          recursive,
        );
      }
    }
  }

  void _tryAddFile(
    File file,
    List<WordSourceFile> files,
    List<WordScanFailure> failures,
  ) {
    final String path = file.path;
    final String ext = _extension(path).toLowerCase();
    if (!kWordExtensions.contains(ext)) return;

    int sizeBytes;
    try {
      sizeBytes = file.lengthSync();
    } on FileSystemException catch (e) {
      failures.add(WordScanFailure(path: path, message: e.osError?.message));
      return;
    }

    files.add(
      WordSourceFile(
        absolutePath: path,
        fileName: file.uri.pathSegments.last,
        extension: ext,
        sizeBytes: sizeBytes,
      ),
    );
  }

  String _extension(String path) {
    final int dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return '';
    return path.substring(dot);
  }
}
