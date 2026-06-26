// lib/features/import/data/services/file_system_pdf_scanner.dart

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/entities/import_request.dart';
import '../../domain/entities/pdf_candidate.dart';
import '../../domain/services/pdf_scanner.dart';
import 'windows_path_policy.dart';

/// Filesystem-backed [PdfScanner].
///
/// Walks the source folder with an explicit stack (so protected roots can be
/// skipped), lists regular files only, matches supported import source
/// extensions case-insensitively, never follows links, continues past per-entry
/// failures, and returns candidates in deterministic (case-insensitive path)
/// order. Read-only throughout.
class FileSystemPdfScanner implements PdfScanner {
  const FileSystemPdfScanner({
    WindowsPathPolicy pathPolicy = const WindowsPathPolicy(),
  }) : _paths = pathPolicy;

  final WindowsPathPolicy _paths;

  static const Set<String> _supportedExtensions = {'.pdf', '.doc'};

  @override
  Future<PdfScanResult> scan(ImportRequest request) async {
    final List<PdfCandidate> candidates = [];
    final List<PdfScanFailure> failures = [];

    final String rootCanonical = _paths.canonicalize(request.sourceFolder);
    final List<String> protectedCanonical = request.protectedRoots.all
        .map(_paths.canonicalize)
        .toList(growable: false);

    bool isProtected(String dirCanonical) => protectedCanonical.any(
      (root) => _paths.isSameOrInside(dirCanonical, root),
    );

    final List<String> stack = [rootCanonical];
    while (stack.isNotEmpty) {
      final String dir = stack.removeLast();

      // Never descend into a protected root.
      if (dir != rootCanonical && isProtected(dir)) continue;

      final List<FileSystemEntity> entries;
      try {
        entries = Directory(dir).listSync(followLinks: false);
      } on FileSystemException catch (e) {
        failures.add(PdfScanFailure(path: dir, message: _safe(e)));
        continue;
      }

      for (final FileSystemEntity entity in entries) {
        // Regular files only: `Link`/`Directory` instances are excluded here.
        if (entity is Directory) {
          if (request.recursive) {
            final String childCanonical = _paths.canonicalize(entity.path);
            if (!isProtected(childCanonical)) stack.add(childCanonical);
          }
          continue;
        }
        if (entity is! File) continue; // Links and other types are skipped.

        final String name = p.basename(entity.path);
        final String ext = p.extension(name).toLowerCase();
        if (!_supportedExtensions.contains(ext)) continue;

        try {
          final FileStat stat = entity.statSync();
          if (stat.type != FileSystemEntityType.file) continue;
          candidates.add(
            PdfCandidate(
              absolutePath: _paths.canonicalize(entity.path),
              fileName: name,
              extension: ext,
              sizeBytes: stat.size < 0 ? 0 : stat.size,
            ),
          );
        } on FileSystemException catch (e) {
          failures.add(PdfScanFailure(path: entity.path, message: _safe(e)));
        }
      }
    }

    candidates.sort(
      (a, b) =>
          a.absolutePath.toLowerCase().compareTo(b.absolutePath.toLowerCase()),
    );
    failures.sort(
      (a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()),
    );

    return PdfScanResult(candidates: candidates, failures: failures);
  }

  /// Reduces a filesystem exception to a short, safe message (no contents).
  String _safe(FileSystemException e) => e.osError?.message ?? 'scan error';
}
