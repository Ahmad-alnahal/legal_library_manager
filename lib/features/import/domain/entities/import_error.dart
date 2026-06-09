// lib/features/import/domain/entities/import_error.dart

import 'package:equatable/equatable.dart';

/// Stable, machine-readable codes for safe import failures.
///
/// Never carry document contents or stack traces. The Arabic UI maps each code
/// to localized text later.
enum ImportErrorCode {
  /// A folder/path failed safety validation.
  folderValidationFailed,

  /// The directory could not be enumerated.
  scanFailed,

  /// The file disappeared or could not be opened for reading.
  unreadable,

  /// Reading bytes for hashing failed.
  hashFailed,

  /// The hashing operation was cancelled.
  hashCancelled,

  /// A persistence/transaction failure while saving import records.
  persistenceFailed,

  /// The file type is not supported in the current phase.
  unsupportedType,

  /// A retried duplicate could not be merged onto the canonical logical document
  /// because the temporary placeholder document still holds business metadata or
  /// dependent records. The physical file is still attached to the canonical
  /// document (duplicate identity preserved); the placeholder is retained for
  /// manual review instead of being deleted.
  duplicateIdentityConflict,

  /// The file is structurally corrupted (zero-byte, missing `%PDF-` header,
  /// or otherwise unreadable as a PDF). The source file is untouched; a safe
  /// failed record is retained for traceability and the file is retryable.
  corrupted,
}

/// A structured, safe import error: a stable [code], an optional safe [path],
/// and a short developer-facing English [message] (never file contents, never a
/// stack trace).
class ImportError extends Equatable {
  const ImportError({required this.code, this.path, this.message});

  final ImportErrorCode code;

  /// A safe filesystem path relevant for recovery, when applicable.
  final String? path;

  /// Short, developer-facing English description. Must not include file bytes,
  /// extracted text, or stack traces.
  final String? message;

  @override
  List<Object?> get props => [code, path, message];

  @override
  String toString() => 'ImportError(${code.name}, $path, "$message")';
}
