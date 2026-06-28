// lib/features/related_files/application/load_pending_candidates_use_case.dart
// ignore_for_file: prefer_initializing_formals

import '../domain/entities/related_file_review_row.dart';
import '../domain/repositories/related_file_candidate_repository.dart';

/// Returns enriched pending candidates for the review UI, confidence-first.
class LoadPendingCandidatesUseCase {
  const LoadPendingCandidatesUseCase(RelatedFileCandidateRepository repository)
    : _repository = repository;

  final RelatedFileCandidateRepository _repository;

  Future<List<RelatedFileReviewRow>> call({int limit = 50}) =>
      _repository.listPendingForReview(limit: limit);
}
