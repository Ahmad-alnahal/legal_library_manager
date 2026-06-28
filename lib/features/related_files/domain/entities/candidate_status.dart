// lib/features/related_files/domain/entities/candidate_status.dart

/// Lifecycle status of a related-file candidate.
///
/// Stored as [key] in `related_file_candidates.status_key`.
/// Do not add new values without a matching DB migration and repository update.
enum CandidateStatus {
  /// Generated automatically; awaiting human review (P2.5).
  pending('pending'),

  /// Human confirmed these files are related.
  confirmed('confirmed'),

  /// Human confirmed these files are unrelated.
  rejected('rejected'),

  /// Silently ignored; do not surface again.
  dismissed('dismissed');

  const CandidateStatus(this.key);

  /// The DB/serialisation key for this status.
  final String key;
}
