// lib/features/managed_copy/domain/entities/managed_copy_persistence_data.dart

/// All data required for the atomic managed-copy success transaction.
///
/// The transaction inserts the managed_copy document_files row, appends
/// copy_completed and copy_verified events, and updates the document
/// workflow — all in one database transaction.
class ManagedCopyPersistenceData {
  const ManagedCopyPersistenceData({
    required this.documentId,
    required this.documentCode,
    required this.operationId,
    required this.managedFilePath,
    required this.managedFileName,
    required this.sha256Hash,
    required this.fileSizeBytes,
    required this.sourceFileId,
    required this.sourceFilePath,
    required this.nowUtc,
  });

  final int documentId;
  final String documentCode;
  final String operationId;
  final String managedFilePath;
  final String managedFileName;
  final String sha256Hash;
  final int fileSizeBytes;

  /// The source file's database ID — used as the FK for copy events.
  final int sourceFileId;

  /// The source absolute path — recorded in copy_completed.sourcePath.
  final String sourceFilePath;

  /// UTC timestamp used for all timestamps in this transaction.
  final DateTime nowUtc;
}
