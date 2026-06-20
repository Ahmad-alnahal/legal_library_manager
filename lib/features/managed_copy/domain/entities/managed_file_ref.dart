// lib/features/managed_copy/domain/entities/managed_file_ref.dart

/// Minimal reference to a managed-copy document_files row used by
/// [CheckManagedCopyHealth] for physical-file presence verification.
///
/// Contains only what the health check needs: the file's row ID, its owning
/// document ID, the stored absolute path, and the current health key. No
/// dart:io or Drift types are imported here.
class ManagedFileRef {
  const ManagedFileRef({
    required this.fileId,
    required this.documentId,
    required this.absolutePath,
    required this.fileHealthKey,
    this.fileSizeBytes = 0,
    this.sha256Hash,
  });

  final int fileId;
  final int documentId;
  final String absolutePath;
  final String fileHealthKey;
  final int fileSizeBytes;
  final String? sha256Hash;
}
