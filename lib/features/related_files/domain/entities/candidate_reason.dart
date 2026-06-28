// lib/features/related_files/domain/entities/candidate_reason.dart

/// The primary signal that caused a candidate pair to be generated.
///
/// Stored as [key] in `related_file_candidates.reason_key`.
/// Reason assignment uses the first matching rule in the generation algorithm.
enum CandidateReason {
  /// One file is `.doc`, the other `.pdf`; they share ≥1 significant
  /// filename token.
  docPdfPair('doc_pdf_pair'),

  /// Both files are in the same directory and share significant filename tokens.
  nearFolderBasename('near_folder_basename'),

  /// The pair was discovered via filename-token buckets; shared document-title
  /// tokens boosted confidence and were the dominant signal.
  titleSimilarity('title_similarity'),

  /// Shared significant filename tokens across different folders.
  similarBasename('similar_basename');

  const CandidateReason(this.key);

  /// The DB/serialisation key for this reason.
  final String key;
}
