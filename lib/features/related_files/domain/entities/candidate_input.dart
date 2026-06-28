// lib/features/related_files/domain/entities/candidate_input.dart

import 'candidate_reason.dart';

/// Input value object supplied to [RelatedFileCandidateRepository.upsertCandidates].
///
/// [fileAId] must always be less than [fileBId] — the caller (use case)
/// canonicalises the ordering before constructing this object. No id or
/// timestamps: those are assigned by the repository.
class CandidateInput {
  const CandidateInput({
    required this.fileAId,
    required this.fileBId,
    required this.reason,
    required this.confidence,
  });

  /// Always the lesser of the two file IDs.
  final int fileAId;

  /// Always the greater of the two file IDs.
  final int fileBId;

  final CandidateReason reason;

  /// Computed confidence score in [0.0, 1.0].
  final double confidence;
}
