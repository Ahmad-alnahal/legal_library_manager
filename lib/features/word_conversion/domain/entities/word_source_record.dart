// lib/features/word_conversion/domain/entities/word_source_record.dart

import 'package:equatable/equatable.dart';

/// Safe projection of a `document_files` row for a Word source file.
///
/// Returned by [WordConversionRepository.loadSourceRecord]. No Drift types leak
/// into this class.
class WordSourceRecord extends Equatable {
  const WordSourceRecord({
    required this.fileId,
    required this.documentId,
    required this.absolutePath,
    required this.extension,
    required this.sha256Hash,
    required this.fileHealthKey,
    required this.fileRoleKey,
  });

  final int fileId;
  final int documentId;

  /// Absolute path to the original source file on disk. Never mutated by
  /// the staging workflow.
  final String absolutePath;

  /// Lowercase extension including the leading dot (e.g. `.doc`).
  final String extension;

  /// SHA-256 hex digest, or null when the file has not yet been hashed.
  final String? sha256Hash;

  /// File health key from the `file_health_statuses` reference table.
  final String fileHealthKey;

  /// File role key from the `file_roles` reference table.
  final String fileRoleKey;

  @override
  List<Object?> get props => [
    fileId,
    documentId,
    absolutePath,
    extension,
    sha256Hash,
    fileHealthKey,
    fileRoleKey,
  ];
}
