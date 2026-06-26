// lib/features/word_conversion/domain/entities/word_source_file.dart

import 'package:equatable/equatable.dart';

/// Allowed Word source extensions (lowercase, dot-prefixed).
///
/// Only the legacy `.doc` binary format is accepted. The `.docx` format is not
/// supported because Microsoft Word COM automation is used for conversion, and
/// `.docx` files produce poor Arabic layout in the generated PDF.
const Set<String> kWordExtensions = {'.doc'};

/// A discovered `.doc` file on disk, before hashing or staging.
///
/// Discovering a Word source file never opens it for writing and never
/// mutates it in any way. The original source is always preserved.
class WordSourceFile extends Equatable {
  const WordSourceFile({
    required this.absolutePath,
    required this.fileName,
    required this.extension,
    required this.sizeBytes,
  });

  /// Canonical absolute path on disk.
  final String absolutePath;

  /// Original display filename (basename), case preserved.
  final String fileName;

  /// Normalized lowercase extension including the leading dot: `.doc`.
  final String extension;

  /// File size in bytes (non-negative).
  final int sizeBytes;

  @override
  List<Object?> get props => [absolutePath, fileName, extension, sizeBytes];
}

/// The result of scanning a folder for Word source files.
class WordScanResult extends Equatable {
  const WordScanResult({required this.files, this.failures = const []});

  final List<WordSourceFile> files;
  final List<WordScanFailure> failures;

  @override
  List<Object?> get props => [files, failures];
}

/// A safe per-entry scan failure (e.g. a file whose metadata could not be
/// read). Carries only a path and a stable message — never file contents.
class WordScanFailure extends Equatable {
  const WordScanFailure({required this.path, this.message});

  final String path;
  final String? message;

  @override
  List<Object?> get props => [path, message];
}
