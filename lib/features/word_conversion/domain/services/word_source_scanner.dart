// lib/features/word_conversion/domain/services/word_source_scanner.dart

import '../entities/word_source_file.dart';

/// Discovers Word source files (`.doc`) under a folder.
///
/// Implementations live in the data layer. They return candidates in
/// deterministic (lexicographic) order, include regular files only, match
/// extensions case-insensitively, never follow symlinks, never mutate any file,
/// and continue past individual entry failures by recording them as
/// [WordScanFailure] entries in the result.
abstract class WordSourceScanner {
  /// Scans [sourceFolder] for Word source files.
  ///
  /// [recursive] controls whether subdirectories are descended into.
  /// [protectedPaths] lists app-owned roots that must never be descended into
  /// even during a recursive scan. The caller is responsible for validating
  /// that [sourceFolder] itself is accessible before calling this.
  Future<WordScanResult> scan(
    String sourceFolder, {
    required bool recursive,
    List<String> protectedPaths = const [],
  });
}
