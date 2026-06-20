// lib/features/managed_copy/domain/entities/source_file_candidate.dart

/// A source_original file being evaluated as the managed-copy origin.
class SourceFileCandidate {
  const SourceFileCandidate({
    required this.fileId,
    required this.documentId,
    required this.absolutePath,
    required this.storedExtension,
    required this.fileHealthKey,
    required this.isPreferred,
    this.sha256Hash,
  });

  final int fileId;
  final int documentId;
  final String absolutePath;

  /// Stored extension from document_files.extension (normalized lowercase dot-prefixed).
  final String storedExtension;
  final String fileHealthKey;
  final bool isPreferred;

  /// Stored SHA-256 hash, or null when not yet computed.
  final String? sha256Hash;
}
