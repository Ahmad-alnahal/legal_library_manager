// lib/features/related_files/data/repositories/drift_related_file_candidate_repository.dart

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/entities/candidate_input.dart';
import '../../domain/entities/candidate_reason.dart';
import '../../domain/entities/candidate_status.dart';
import '../../domain/entities/related_file_candidate.dart';
import '../../domain/repositories/related_file_candidate_repository.dart';

/// Drift-backed implementation of [RelatedFileCandidateRepository].
///
/// All writes use INSERT OR IGNORE so existing pairs (regardless of their
/// current status) are never overwritten. [updateStatus] is the only mutation
/// that modifies an existing row.
class DriftRelatedFileCandidateRepository
    implements RelatedFileCandidateRepository {
  DriftRelatedFileCandidateRepository(this._db);

  final AppDatabase _db;

  @override
  Future<int> upsertCandidates(
    List<CandidateInput> candidates,
    DateTime now,
  ) async {
    if (candidates.isEmpty) return 0;
    final nowIso = now.toIso8601String();
    int inserted = 0;
    for (final c in candidates) {
      await _db.customInsert(
        'INSERT OR IGNORE INTO related_file_candidates '
        '(file_a_id, file_b_id, reason_key, confidence, '
        ' status_key, created_at, updated_at) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
        variables: [
          Variable.withInt(c.fileAId),
          Variable.withInt(c.fileBId),
          Variable.withString(c.reason.key),
          Variable.withReal(c.confidence),
          Variable.withString(CandidateStatus.pending.key),
          Variable.withString(nowIso),
          Variable.withString(nowIso),
        ],
        updates: {_db.relatedFileCandidates},
      );
      // changes() returns the actual number of rows modified by the most recent
      // statement — 0 when INSERT OR IGNORE skips a conflicting row.
      final changed = await _db
          .customSelect('SELECT changes() AS n')
          .getSingle();
      inserted += changed.read<int>('n');
    }
    return inserted;
  }

  @override
  Future<List<RelatedFileCandidate>> listByStatus(
    CandidateStatus status,
  ) async {
    final rows = await (_db.select(
      _db.relatedFileCandidates,
    )..where((t) => t.statusKey.equals(status.key))).get();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<List<RelatedFileCandidate>> listForFile(int fileId) async {
    final rows = await (_db.select(
      _db.relatedFileCandidates,
    )..where((t) => t.fileAId.equals(fileId) | t.fileBId.equals(fileId))).get();
    return rows.map(_toEntity).toList();
  }

  @override
  Future<void> updateStatus(
    int candidateId,
    CandidateStatus status,
    DateTime now,
  ) async {
    final count =
        await (_db.update(
          _db.relatedFileCandidates,
        )..where((t) => t.id.equals(candidateId))).write(
          RelatedFileCandidatesCompanion(
            statusKey: Value(status.key),
            updatedAt: Value(now.toIso8601String()),
          ),
        );
    if (count == 0) {
      throw StateError('updateStatus: candidate $candidateId not found');
    }
  }

  RelatedFileCandidate _toEntity(RelatedFileCandidateRow row) {
    return RelatedFileCandidate(
      id: row.id,
      fileAId: row.fileAId,
      fileBId: row.fileBId,
      reason: CandidateReason.values.firstWhere(
        (r) => r.key == row.reasonKey,
        orElse: () => CandidateReason.similarBasename,
      ),
      confidence: row.confidence,
      status: CandidateStatus.values.firstWhere(
        (s) => s.key == row.statusKey,
        orElse: () => CandidateStatus.pending,
      ),
      createdAt: DateTime.parse(row.createdAt),
      updatedAt: DateTime.parse(row.updatedAt),
    );
  }
}
