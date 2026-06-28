// lib/features/related_files/domain/entities/candidate_file_info.dart

/// Source-file facts consumed by [GenerateRelatedFileCandidatesUseCase].
///
/// The caller (import batch result, future DB query, or test fixture) supplies
/// this list. The use case never reads the database itself.
///
/// No Drift types. No Flutter imports.
class CandidateFileInfo {
  const CandidateFileInfo({
    required this.fileId,
    required this.documentId,
    required this.absolutePath,
    required this.extension,
    this.sha256Hash,
    this.documentTitle,
  });

  final int fileId;

  /// Used to exclude same-document pairs (covers already-paired .doc+.pdf).
  final int documentId;

  /// Full absolute Windows path (e.g. `r'C:\legal\contract.pdf'`).
  final String absolutePath;

  /// Lower-case with dot, e.g. `'.pdf'`, `'.doc'`.
  final String extension;

  /// `null` for corrupted/failed files. Pairs sharing a non-null hash are
  /// exact duplicates and are excluded from candidate generation.
  final String? sha256Hash;

  /// The document's title metadata if already classified. `null` = not yet
  /// classified. Title similarity is a scoring boost only — never a primary
  /// discovery signal. No OCR or content parsing is performed.
  final String? documentTitle;
}
