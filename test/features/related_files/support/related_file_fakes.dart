// test/features/related_files/support/related_file_fakes.dart

import 'package:legal_library_manager/features/related_files/domain/entities/candidate_input.dart';
import 'package:legal_library_manager/features/related_files/domain/entities/candidate_status.dart';
import 'package:legal_library_manager/features/related_files/domain/entities/related_file_candidate.dart';
import 'package:legal_library_manager/features/related_files/domain/repositories/related_file_candidate_repository.dart';

/// In-memory fake for [RelatedFileCandidateRepository].
///
/// Tracks every [upsertCandidates] call. Returns the number of newly inserted
/// pairs (pairs not already present in [inserted]). Status updates are not
/// persisted — override if needed.
class FakeRelatedFileCandidateRepository
    implements RelatedFileCandidateRepository {
  final List<CandidateInput> inserted = [];
  final Set<String> _seenPairKeys = {};

  @override
  Future<int> upsertCandidates(
    List<CandidateInput> candidates,
    DateTime now,
  ) async {
    int newCount = 0;
    for (final c in candidates) {
      final key = '${c.fileAId}:${c.fileBId}';
      if (_seenPairKeys.add(key)) {
        inserted.add(c);
        newCount++;
      }
    }
    return newCount;
  }

  @override
  Future<List<RelatedFileCandidate>> listByStatus(
    CandidateStatus status,
  ) async => const [];

  @override
  Future<List<RelatedFileCandidate>> listForFile(int fileId) async => const [];

  @override
  Future<void> updateStatus(
    int candidateId,
    CandidateStatus status,
    DateTime now,
  ) async {}
}
