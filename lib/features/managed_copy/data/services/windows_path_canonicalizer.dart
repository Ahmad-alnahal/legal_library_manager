// lib/features/managed_copy/data/services/windows_path_canonicalizer.dart

import 'dart:io';

import '../../domain/services/path_canonicalizer.dart';

/// dart:io-backed [PathCanonicalizer] for Windows.
///
/// Uses [FileSystemEntity.resolveSymbolicLinksSync] /
/// [Directory.resolveSymbolicLinksSync] / [File.resolveSymbolicLinksSync] to
/// follow symlinks, junctions, and reparse points, and to collapse `.` / `..`
/// segments. Only paths that physically exist can be resolved; non-existent
/// paths return null.
class WindowsPathCanonicalizer implements PathCanonicalizer {
  const WindowsPathCanonicalizer();

  @override
  String? canonicalize(String path) {
    try {
      final type = FileSystemEntity.typeSync(path, followLinks: false);
      switch (type) {
        case FileSystemEntityType.directory:
          return Directory(path).resolveSymbolicLinksSync();
        case FileSystemEntityType.file:
          return File(path).resolveSymbolicLinksSync();
        case FileSystemEntityType.link:
          // Explicit symlink/junction: resolve through the link.
          return File(path).resolveSymbolicLinksSync();
        case FileSystemEntityType.notFound:
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }
}
