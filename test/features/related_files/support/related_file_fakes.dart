// test/features/related_files/support/related_file_fakes.dart

import 'package:legal_library_manager/features/related_files/domain/entities/candidate_input.dart';
import 'package:legal_library_manager/features/related_files/domain/entities/candidate_reason.dart';
import 'package:legal_library_manager/features/related_files/domain/entities/candidate_status.dart';
import 'package:legal_library_manager/features/related_files/domain/entities/related_file_candidate.dart';
import 'package:legal_library_manager/features/related_files/domain/entities/related_file_review_row.dart';
import 'package:legal_library_manager/features/related_files/domain/repositories/related_file_candidate_repository.dart';

/// Creates a populated [RelatedFileReviewRow] for tests.
RelatedFileReviewRow fakeReviewRow(int id, {double confidence = 0.75}) =>
    RelatedFileReviewRow(
      candidateId: id,
      confidence: confidence,
      reason: CandidateReason.similarBasename,
      createdAt: DateTime.utc(2026, 6, 28),
      fileAId: id * 2,
      fileAName: 'file_a_$id.pdf',
      fileAPath: 'C:\\docs\\file_a_$id.pdf',
      fileAExtension: '.pdf',
      documentAId: id * 10,
      documentATitle: null,
      documentACode: null,
      documentAWorkflowStatus: null,
      fileBId: id * 2 + 1,
      fileBName: 'file_b_$id.doc',
      fileBPath: 'C:\\docs\\file_b_$id.doc',
      fileBExtension: '.doc',
      documentBId: id * 10 + 1,
      documentBTitle: null,
      documentBCode: null,
      documentBWorkflowStatus: null,
    );

/// In-memory fake for [RelatedFileCandidateRepository].
///
/// Tracks every [upsertCandidates] call. Returns the number of newly inserted
/// pairs (pairs not already present in [inserted]). Status updates optimistically
/// remove matching rows from [_pendingRows].
class FakeRelatedFileCandidateRepository
    implements RelatedFileCandidateRepository {
  FakeRelatedFileCandidateRepository({List<RelatedFileReviewRow>? rows})
    : _pendingRows = rows ?? [];

  final List<CandidateInput> inserted = [];
  final Set<String> _seenPairKeys = {};

  /// Pre-seeded review rows returned by [listPendingForReview].
  List<RelatedFileReviewRow> _pendingRows;

  /// Set to true to make [updateStatus] throw.
  bool failUpdateStatus = false;

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
  ) async {
    if (failUpdateStatus) throw StateError('updateStatus failed (test)');
    _pendingRows = _pendingRows
        .where((r) => r.candidateId != candidateId)
        .toList();
  }

  @override
  Future<List<RelatedFileReviewRow>> listPendingForReview({
    int limit = 50,
  }) async => _pendingRows.take(limit).toList();
}
