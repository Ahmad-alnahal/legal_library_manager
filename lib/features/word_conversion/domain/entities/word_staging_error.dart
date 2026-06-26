// lib/features/word_conversion/domain/entities/word_staging_error.dart

/// Stable error codes for Word-source staging operations.
enum WordStagingError {
  /// The managed library root is not configured; the staging area cannot be derived.
  noManagedLibraryRoot,

  /// The staging directory cannot be created or accessed.
  stagingDirectoryUnavailable,

  /// The source file record does not exist in the database.
  sourceFileNotFound,

  /// The file record's role is not `source_original`, or its extension is not
  /// a Word document format (`.doc`).
  sourceFileNotWordDocument,

  /// The source file record has no SHA-256 hash. Staging requires a known hash
  /// for content-addressed naming.
  sourceHashNotAvailable,

  /// The staging copy operation failed. The original source is preserved.
  stagingCopyFailed,

  /// Database persistence failed after a successful staging copy.
  persistenceFailed,
}
