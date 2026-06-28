// lib/features/related_files/domain/repositories/related_file_candidate_repository.dart

import '../entities/candidate_input.dart';
import '../entities/candidate_status.dart';
import '../entities/related_file_candidate.dart';

/// Persistence contract for related-file candidates.
///
/// All Drift types are confined to the data layer; implementations must not
/// be referenced from domain or application code.
abstract class RelatedFileCandidateRepository {
  /// Inserts each candidate whose `(fileAId, fileBId)` pair does not already
  /// exist. Existing pairs are silently skipped (INSERT OR IGNORE semantics) —
  /// their current [CandidateStatus] (confirmed, rejected, dismissed) is
  /// preserved. [now] is used for `created_at` and `updated_at` on new rows.
  ///
  /// The caller must guarantee `input.fileAId < input.fileBId` for every item.
  /// Returns the number of newly inserted rows.
  Future<int> upsertCandidates(List<CandidateInput> candidates, DateTime now);

  /// Returns all candidates with the given [status], in insertion order.
  Future<List<RelatedFileCandidate>> listByStatus(CandidateStatus status);

  /// Returns all candidates where [fileId] is either `file_a_id` or
  /// `file_b_id`, in insertion order.
  Future<List<RelatedFileCandidate>> listForFile(int fileId);

  /// Updates the status of a single candidate and sets `updated_at` to [now].
  /// Throws [StateError] if [candidateId] does not exist.
  Future<void> updateStatus(
    int candidateId,
    CandidateStatus status,
    DateTime now,
  );
}
