// lib/features/related_files/data/repositories/drift_related_file_candidate_repository.dart

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/entities/candidate_input.dart';
import '../../domain/entities/candidate_reason.dart';
import '../../domain/entities/candidate_status.dart';
import '../../domain/entities/related_file_candidate.dart';
import '../../domain/entities/related_file_review_row.dart';
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

  @override
  Future<List<RelatedFileReviewRow>> listPendingForReview({
    int limit = 50,
  }) async {
    // Raw JOIN query: related_file_candidates → document_files (×2) → documents (×2)
    // Column aliases use prefixes (c_, fa_, fb_, da_, db_) to avoid collisions.
    // db2 alias avoids conflicting with SQLite's reserved "db" identifier.
    // Ordered highest-confidence first so users see the best matches at the top.
    final rows = await _db
        .customSelect(
          '''
      SELECT
        c.id             AS c_id,
        c.confidence     AS c_confidence,
        c.reason_key     AS c_reason_key,
        c.created_at     AS c_created_at,
        fa.id            AS fa_id,
        fa.file_name     AS fa_file_name,
        fa.absolute_path AS fa_absolute_path,
        fa.extension     AS fa_extension,
        fb.id            AS fb_id,
        fb.file_name     AS fb_file_name,
        fb.absolute_path AS fb_absolute_path,
        fb.extension     AS fb_extension,
        da.id            AS da_id,
        da.title         AS da_title,
        da.document_code AS da_document_code,
        da.workflow_status_key AS da_workflow_status_key,
        db2.id           AS db_id,
        db2.title        AS db_title,
        db2.document_code AS db_document_code,
        db2.workflow_status_key AS db_workflow_status_key
      FROM related_file_candidates c
      JOIN document_files fa  ON c.file_a_id = fa.id
      JOIN document_files fb  ON c.file_b_id = fb.id
      JOIN documents      da  ON fa.document_id = da.id
      JOIN documents      db2 ON fb.document_id = db2.id
      WHERE c.status_key = ?
      ORDER BY c.confidence DESC
      LIMIT ?
      ''',
          variables: [
            Variable.withString(CandidateStatus.pending.key),
            Variable.withInt(limit),
          ],
          readsFrom: {
            _db.relatedFileCandidates,
            _db.documentFiles,
            _db.documents,
          },
        )
        .get();
    return rows.map(_toReviewRow).toList();
  }

  // ── Mappers ───────────────────────────────────────────────────────────────

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

  RelatedFileReviewRow _toReviewRow(QueryRow row) => RelatedFileReviewRow(
    candidateId: row.read<int>('c_id'),
    confidence: row.read<double>('c_confidence'),
    reason: CandidateReason.values.firstWhere(
      (r) => r.key == row.read<String>('c_reason_key'),
      orElse: () => CandidateReason.similarBasename,
    ),
    createdAt: DateTime.parse(row.read<String>('c_created_at')),
    fileAId: row.read<int>('fa_id'),
    fileAName: row.read<String>('fa_file_name'),
    fileAPath: row.read<String>('fa_absolute_path'),
    fileAExtension: row.read<String>('fa_extension'),
    documentAId: row.read<int>('da_id'),
    documentATitle: row.readNullable<String>('da_title'),
    documentACode: row.readNullable<String>('da_document_code'),
    documentAWorkflowStatus: row.readNullable<String>('da_workflow_status_key'),
    fileBId: row.read<int>('fb_id'),
    fileBName: row.read<String>('fb_file_name'),
    fileBPath: row.read<String>('fb_absolute_path'),
    fileBExtension: row.read<String>('fb_extension'),
    documentBId: row.read<int>('db_id'),
    documentBTitle: row.readNullable<String>('db_title'),
    documentBCode: row.readNullable<String>('db_document_code'),
    documentBWorkflowStatus: row.readNullable<String>('db_workflow_status_key'),
  );
}
