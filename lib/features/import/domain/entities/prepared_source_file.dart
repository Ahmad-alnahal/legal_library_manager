// lib/features/import/domain/entities/prepared_source_file.dart

import 'package:equatable/equatable.dart';

import 'pdf_health_result.dart';

/// A fully-inspected source file ready for transactional persistence: its
/// canonical path, display name, size, MIME, computed SHA-256, and health.
///
/// Used for the success paths (`imported_new`, `imported_duplicate_path`) and
/// for the `already_imported` short-circuit. The [sha256] is always a validated
/// lowercase 64-hex digest computed from the bytes — never a supplied hash.
class PreparedSourceFile extends Equatable {
  const PreparedSourceFile({
    required this.canonicalPath,
    required this.displayName,
    required this.extension,
    required this.sizeBytes,
    required this.sha256,
    required this.health,
    this.mimeType,
    this.pageCount,
  });

  final String canonicalPath;
  final String displayName;

  /// Normalized lowercase extension including the dot, e.g. `.pdf`.
  final String extension;
  final int sizeBytes;

  /// Lowercase 64-character hexadecimal SHA-256 of the file bytes.
  final String sha256;
  final PdfHealthStatus health;
  final String? mimeType;
  final int? pageCount;

  @override
  List<Object?> get props => [
    canonicalPath,
    displayName,
    extension,
    sizeBytes,
    sha256,
    health,
    mimeType,
    pageCount,
  ];
}

/// A source file that could not be hashed (unreadable file, or hashing failed).
///
/// Persisted with sufficient safe metadata, with health `unreadable`/`corrupted`
/// and a `null` SHA-256. Never joined to a duplicate group.
class FailedSourceFile extends Equatable {
  const FailedSourceFile({
    required this.canonicalPath,
    required this.displayName,
    required this.extension,
    required this.sizeBytes,
    required this.health,
    this.mimeType,
    this.errorCode,
    this.safeMessage,
  });

  final String canonicalPath;
  final String displayName;
  final String extension;

  /// Non-negative; may be `0` when the size could not be read.
  final int sizeBytes;

  /// `unreadable` or `corrupted`.
  final PdfHealthStatus health;
  final String? mimeType;

  /// Stable safe error code (e.g. `hash_failed`, `unreadable`).
  final String? errorCode;

  /// Short safe message; never file contents.
  final String? safeMessage;

  @override
  List<Object?> get props => [
    canonicalPath,
    displayName,
    extension,
    sizeBytes,
    health,
    mimeType,
    errorCode,
    safeMessage,
  ];
}

/// A minimal reference to an already-imported file matched by absolute path.
class ExistingFileRef extends Equatable {
  const ExistingFileRef({required this.fileId, required this.documentId});

  final int fileId;
  final int documentId;

  @override
  List<Object?> get props => [fileId, documentId];
}
