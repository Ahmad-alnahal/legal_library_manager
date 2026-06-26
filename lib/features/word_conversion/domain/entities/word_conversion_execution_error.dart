// lib/features/word_conversion/domain/entities/word_conversion_execution_error.dart

/// Stable error codes for the [ConvertStagedWordSource] use case.
enum WordConversionExecutionError {
  /// No `file_conversions` row was found for the given ID.
  conversionNotFound,

  /// The conversion row is not in `pending_conversion` status, and the
  /// current status is not a recognized completed state.
  conversionNotPending,

  /// The conversion is already in `converting` status (possible crash
  /// recovery). Manual status reset is required before retrying.
  conversionAlreadyInProgress,

  /// The source `document_files` record was not found.
  sourceNotFound,

  /// The managed library root is not configured.
  libraryRootNotConfigured,

  /// The staged Word file is missing from the staging area.
  stagedFileNotFound,

  /// Microsoft Word could not be found on this machine.
  microsoftWordUnavailable,

  /// The output directory could not be created or accessed.
  outputDirectoryUnavailable,

  /// Microsoft Word exited with a non-zero status or could not be launched.
  processFailed,

  /// The expected PDF file was not created by Microsoft Word.
  outputNotCreated,

  /// The generated PDF file is empty (zero bytes).
  outputEmpty,

  /// The generated file does not begin with the `%PDF` header.
  outputNotPdf,

  /// SHA-256 hashing of the generated PDF failed.
  hashFailed,

  /// The database transaction to finalize the conversion failed.
  persistenceFailed,

  /// The document code could not be allocated (code space exhausted or DB
  /// error).
  documentCodeAllocationFailed,
}
