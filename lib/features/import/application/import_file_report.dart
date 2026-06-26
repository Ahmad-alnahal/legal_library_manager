// lib/features/import/application/import_file_report.dart

import 'package:equatable/equatable.dart';

import '../domain/entities/import_error.dart';
import '../domain/entities/import_file_result.dart';
import '../domain/entities/pdf_candidate.dart';

/// Per-file status for the import report UI.
///
/// Mirrors the domain [ImportFileOutcome] result keys plus an application-only
/// [persistenceFailed] for files that hashed successfully but whose database
/// save failed (no domain result key exists for that, and the schema is not
/// expanded).
enum ImportFileStatus {
  importedNew,
  importedDuplicatePath,
  alreadyImported,
  unsupportedType,
  unreadable,
  hashFailed,
  scanFailed,
  persistenceFailed,

  /// The file is structurally corrupted (zero-byte, bad PDF header, etc.).
  /// Never hashed or grouped as a duplicate. Retryable in case the source is
  /// later repaired or replaced.
  corrupted,

  /// A `.doc` source that was detected as a paired counterpart to an existing
  /// `.pdf` with the same normalized basename in the same folder. Hashed and
  /// attached to the same document as the PDF. No conversion task is created.
  pairedWordSource;

  /// Whether a file with this status can be re-attempted by "retry failed".
  bool get isRetryable =>
      this == unreadable ||
      this == hashFailed ||
      this == scanFailed ||
      this == persistenceFailed ||
      this == corrupted;

  /// Whether this status represents a failure (for batch counters).
  bool get isFailure => isRetryable || this == unsupportedType;

  static ImportFileStatus fromOutcome(ImportFileOutcome outcome) {
    return switch (outcome) {
      ImportFileOutcome.importedNew => ImportFileStatus.importedNew,
      ImportFileOutcome.importedDuplicatePath =>
        ImportFileStatus.importedDuplicatePath,
      ImportFileOutcome.alreadyImported => ImportFileStatus.alreadyImported,
      ImportFileOutcome.unsupportedType => ImportFileStatus.unsupportedType,
      ImportFileOutcome.unreadable => ImportFileStatus.unreadable,
      ImportFileOutcome.hashFailed => ImportFileStatus.hashFailed,
      ImportFileOutcome.scanFailed => ImportFileStatus.scanFailed,
      ImportFileOutcome.corrupted => ImportFileStatus.corrupted,
      ImportFileOutcome.pairedWordSource => ImportFileStatus.pairedWordSource,
    };
  }
}

/// A single file's result inside an import run report.
///
/// Carries only safe, display-ready data: the file name, a safe path, the
/// status, and an optional safe error. The original [candidate] (when present)
/// lets "retry" re-attempt a file without rescanning the whole folder.
class ImportFileReport extends Equatable {
  const ImportFileReport({
    required this.fileName,
    required this.path,
    required this.status,
    this.error,
    this.candidate,
    this.documentId,
    this.fileId,
  });

  final String fileName;
  final String path;
  final ImportFileStatus status;
  final ImportError? error;

  /// The discovered candidate, when this report came from a scanned file.
  final PdfCandidate? candidate;
  final int? documentId;
  final int? fileId;

  bool get isRetryable => status.isRetryable && candidate != null;

  ImportFileReport copyWith({
    ImportFileStatus? status,
    ImportError? error,
    int? documentId,
    int? fileId,
  }) {
    return ImportFileReport(
      fileName: fileName,
      path: path,
      status: status ?? this.status,
      error: error ?? this.error,
      candidate: candidate,
      documentId: documentId ?? this.documentId,
      fileId: fileId ?? this.fileId,
    );
  }

  @override
  List<Object?> get props => [
    fileName,
    path,
    status,
    error,
    candidate,
    documentId,
    fileId,
  ];
}
