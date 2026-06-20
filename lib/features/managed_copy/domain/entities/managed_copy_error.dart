// lib/features/managed_copy/domain/entities/managed_copy_error.dart

/// Stable, machine-readable error codes for managed-copy failures.
///
/// The [name] of each variant is persisted to [file_events.error_code] and
/// must remain stable. Arabic UI strings map these codes in later milestones.
enum ManagedCopyError {
  /// No document row exists for the requested ID.
  documentNotFound,

  /// Document workflow status is not exactly 'classified'.
  notClassified,

  /// Document already has a managed-copy file record.
  alreadyCopied,

  /// managed_library_root or database_backup_root settings are not configured.
  rootsNotConfigured,

  /// Configured roots overlap, share a boundary, or are not absolute existing
  /// directories. Includes source-location overlap with managed files dir.
  unsafeRoots,

  /// A configured root is absolute but its directory is currently missing or
  /// inaccessible. The storage configuration requires attention (the folder can
  /// be explicitly recreated from Settings) before any managed copy can run.
  rootsMissing,

  /// No source_original, healthy, .pdf file exists for this document.
  noEligibleSource,

  /// More than one eligible source exists and none is uniquely preferred.
  ambiguousSource,

  /// The selected source file does not exist on the filesystem.
  missingSource,

  /// The source file's extension (stored or actual path) is not .pdf.
  unsupportedSource,

  /// The pre-copy SQLite backup could not be created or verified.
  backupFailed,

  /// The final managed target path already exists.
  targetConflict,

  /// The temporary copy target path already exists.
  temporaryTargetConflict,

  /// Byte-level copy from source to temporary path failed.
  copyFailed,

  /// SHA-256 hashing of the source or temporary copy failed.
  hashFailed,

  /// SHA-256 of the copy does not match the trusted source digest.
  hashMismatch,

  /// Renaming the verified temporary copy to the final path failed.
  finalizationFailed,

  /// File was finalized but transactional DB persistence subsequently failed.
  /// The verified file is preserved; manual reconciliation is required.
  databasePersistenceFailed,

  /// An unexpected error that does not fit a more specific category.
  unexpectedFailure,

  /// The allocated or existing document code does not match DOC-[0-9]{7}.
  /// Includes codes that are path-like, contain separators, or are otherwise
  /// malformed in a way that would make them unsafe as filename components.
  malformedDocumentCode,

  /// All seven-digit document code slots (DOC-0000001 … DOC-9999999) have
  /// been allocated. No new code can be issued.
  codeSpaceExhausted,

  /// A mandatory audit event (backup_created or copy_started) could not be
  /// persisted to the database. The copy was blocked before any bytes were
  /// written.
  auditEventFailed,

  /// The size of the finalized managed-copy file could not be read from the
  /// filesystem. The file is preserved on disk for M11 reconciliation.
  fileSizeUnreadable,

  /// A previously-missing managed-copy file was found on disk with a matching
  /// hash and size, and its database record was restored to healthy.
  /// Returned instead of [alreadyCopied] so the UI can show a distinct,
  /// positive confirmation rather than a "nothing to do" message.
  restoredFromDisk,
}
