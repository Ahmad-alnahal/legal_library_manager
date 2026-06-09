// lib/features/import/domain/entities/pdf_candidate.dart

import 'package:equatable/equatable.dart';

/// A discovered `.pdf` file on disk, before hashing or health inspection.
///
/// Persistence-agnostic and read-only: discovering a candidate never opens the
/// file for writing or mutates it in any way.
class PdfCandidate extends Equatable {
  const PdfCandidate({
    required this.absolutePath,
    required this.fileName,
    required this.extension,
    required this.sizeBytes,
  });

  /// Canonical absolute path on disk.
  final String absolutePath;

  /// Original display filename (basename), case preserved.
  final String fileName;

  /// Normalized lowercase extension including the dot, e.g. `.pdf`.
  final String extension;

  /// File size in bytes (non-negative).
  final int sizeBytes;

  @override
  List<Object?> get props => [absolutePath, fileName, extension, sizeBytes];
}

/// The result of scanning a folder: the deterministically ordered candidates
/// plus any per-entry failures encountered (scanning continues past failures).
class PdfScanResult extends Equatable {
  const PdfScanResult({required this.candidates, this.failures = const []});

  final List<PdfCandidate> candidates;

  /// Safe, structured failures for entries that could not be inspected. Each
  /// becomes a `scan_failed` per-file result upstream.
  final List<PdfScanFailure> failures;

  @override
  List<Object?> get props => [candidates, failures];
}

/// A safe, per-entry scan failure (e.g. a file whose metadata could not be
/// read). Carries only a path and a stable message — never file contents.
class PdfScanFailure extends Equatable {
  const PdfScanFailure({required this.path, this.message});

  final String path;
  final String? message;

  @override
  List<Object?> get props => [path, message];
}
