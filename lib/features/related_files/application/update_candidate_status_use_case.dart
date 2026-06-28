// lib/features/related_files/application/update_candidate_status_use_case.dart
// ignore_for_file: prefer_initializing_formals

import '../../../core/time/clock.dart';
import '../domain/entities/candidate_status.dart';
import '../domain/repositories/related_file_candidate_repository.dart';

/// Updates a candidate's status to confirmed, rejected, or dismissed.
///
/// P2.5 scope: confirming only marks the candidate as confirmed.
/// Document merging / file relinking is explicitly deferred to P2.6.
class UpdateCandidateStatusUseCase {
  const UpdateCandidateStatusUseCase(
    RelatedFileCandidateRepository repository,
    Clock clock,
  ) : _repository = repository,
      _clock = clock;

  final RelatedFileCandidateRepository _repository;
  final Clock _clock;

  Future<void> call(int candidateId, CandidateStatus status) =>
      _repository.updateStatus(candidateId, status, _clock.nowUtc());
}
