// lib/features/related_files/application/related_candidate_generation_result.dart

/// Statistics returned by [GenerateRelatedFileCandidatesUseCase].
///
/// Used by tests to prove bounded comparison behaviour without relying on
/// wall-clock timing.
class RelatedCandidateGenerationResult {
  const RelatedCandidateGenerationResult({
    required this.comparedPairCount,
    required this.generatedCandidateCount,
    required this.insertedCount,
    required this.skippedLargeBucketCount,
  });

  /// Total pairs evaluated after same-document and exact-hash exclusion.
  /// Deduplicated across multiple shared bucket keys.
  final int comparedPairCount;

  /// Pairs that met or exceeded the minimum confidence threshold (0.20) and
  /// were submitted for insertion.
  final int generatedCandidateCount;

  /// Pairs actually newly inserted into the database (INSERT OR IGNORE;
  /// existing pairs not counted).
  final int insertedCount;

  /// Buckets skipped because they exceeded [GenerateRelatedFileCandidatesUseCase.maxBucketSize].
  final int skippedLargeBucketCount;
}
