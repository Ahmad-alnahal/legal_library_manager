// lib/features/duplicates/data/repositories/drift_duplicate_review_repository.dart

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/entities/duplicate_group_details.dart';
import '../../domain/entities/duplicate_group_file_item.dart';
import '../../domain/entities/duplicate_group_summary.dart';
import '../../domain/repositories/duplicate_review_repository.dart';

/// Drift-backed read-only implementation of [DuplicateReviewRepository].
///
/// Only groups with at least 2 members are returned â€” single-entry groups
/// produced by transient import state are excluded. No writes are performed.
class DriftDuplicateReviewRepository implements DuplicateReviewRepository {
  DriftDuplicateReviewRepository(this._db);

  final AppDatabase _db;

  @override
  Future<DuplicateGroupPage> getGroups({int offset = 0, int limit = 50}) async {
    if (offset < 0 || limit < 1 || limit > 200) {
      throw ArgumentError('Pagination requires offset >= 0 and limit 1..200.');
    }

    final countRow = await _db
        .customSelect(
          '''
SELECT
  COUNT(*) AS total,
  SUM(
    CASE
      WHEN review_status_key IN ('unreviewed', 'archived_for_later') THEN 1
      ELSE 0
    END
  ) AS pending_review_total
FROM (
  SELECT dg.id, dg.review_status_key
  FROM duplicate_groups dg
  JOIN duplicate_group_members dgm ON dgm.duplicate_group_id = dg.id
  GROUP BY dg.id
  HAVING COUNT(dgm.file_id) >= 2
) sub
''',
          readsFrom: {_db.duplicateGroups, _db.duplicateGroupMembers},
        )
        .getSingle();
    final total = countRow.read<int>('total');
    final pendingReviewTotal =
        countRow.readNullable<int>('pending_review_total') ?? 0;

    final rows = await _db
        .customSelect(
          '''
SELECT
  dg.id,
  dg.group_code,
  dg.sha256_hash,
  dg.review_status_key,
  dg.preferred_file_id,
  dg.created_at,
  dg.updated_at,
  (
    SELECT COALESCE(NULLIF(d2.title, ''), NULLIF(df2.file_name, ''), d2.document_code, dg.group_code)
    FROM duplicate_group_members dgm2
    JOIN document_files df2 ON df2.id = dgm2.file_id
    JOIN documents d2 ON d2.id = df2.document_id
    WHERE dgm2.duplicate_group_id = dg.id
    ORDER BY CASE WHEN dg.preferred_file_id = dgm2.file_id THEN 0 ELSE 1 END,
      d2.document_code ASC,
      df2.id ASC
    LIMIT 1
  ) AS display_name,
  COUNT(dgm.file_id) AS member_count
FROM duplicate_groups dg
JOIN duplicate_group_members dgm ON dgm.duplicate_group_id = dg.id
GROUP BY dg.id
HAVING COUNT(dgm.file_id) >= 2
ORDER BY CASE dg.review_status_key
    WHEN 'unreviewed' THEN 0
    WHEN 'archived_for_later' THEN 1
    ELSE 2
  END,
  dg.updated_at DESC,
  dg.id DESC
LIMIT ? OFFSET ?
''',
          variables: [Variable<int>(limit), Variable<int>(offset)],
          readsFrom: {_db.duplicateGroups, _db.duplicateGroupMembers},
        )
        .get();

    return DuplicateGroupPage(
      groups: rows.map(_mapSummary).toList(growable: false),
      totalCount: total,
      pendingReviewCount: pendingReviewTotal,
      offset: offset,
      limit: limit,
    );
  }

  @override
  Future<DuplicateGroupDetails> getGroupDetails(int groupId) async {
    final groupRow = await _db
        .customSelect(
          '''
SELECT
  dg.id,
  dg.group_code,
  dg.sha256_hash,
  dg.review_status_key,
  dg.preferred_file_id,
  dg.notes,
  dg.created_at,
  dg.updated_at,
  (
    SELECT COALESCE(NULLIF(d2.title, ''), NULLIF(df2.file_name, ''), d2.document_code, dg.group_code)
    FROM duplicate_group_members dgm2
    JOIN document_files df2 ON df2.id = dgm2.file_id
    JOIN documents d2 ON d2.id = df2.document_id
    WHERE dgm2.duplicate_group_id = dg.id
    ORDER BY CASE WHEN dg.preferred_file_id = dgm2.file_id THEN 0 ELSE 1 END,
      d2.document_code ASC,
      df2.id ASC
    LIMIT 1
  ) AS display_name,
  (
    SELECT COUNT(*)
    FROM duplicate_group_members dgm2
    WHERE dgm2.duplicate_group_id = dg.id
  ) AS member_count
FROM duplicate_groups dg
WHERE dg.id = ?
''',
          variables: [Variable<int>(groupId)],
          readsFrom: {_db.duplicateGroups, _db.duplicateGroupMembers},
        )
        .getSingleOrNull();

    if (groupRow == null) {
      throw StateError('Duplicate group $groupId not found.');
    }

    final summary = _mapSummary(groupRow);
    final notes = groupRow.readNullable<String>('notes');

    final memberRows = await _db
        .customSelect(
          '''
SELECT
  dgm.file_id,
  dgm.is_hidden_from_search,
  dgm.added_at,
  df.document_id,
  df.file_role_key,
  df.file_name,
  df.absolute_path,
  df.file_health_key,
  df.file_size_bytes,
  CASE WHEN dg.preferred_file_id = dgm.file_id THEN 1 ELSE 0 END AS is_preferred,
  d.document_code,
  d.title,
  d.workflow_status_key
FROM duplicate_group_members dgm
JOIN duplicate_groups dg ON dg.id = dgm.duplicate_group_id
JOIN document_files df ON df.id = dgm.file_id
JOIN documents d ON d.id = df.document_id
WHERE dgm.duplicate_group_id = ?
ORDER BY is_preferred DESC, d.document_code ASC, df.id ASC
''',
          variables: [Variable<int>(groupId)],
          readsFrom: {
            _db.duplicateGroupMembers,
            _db.duplicateGroups,
            _db.documentFiles,
            _db.documents,
          },
        )
        .get();

    return DuplicateGroupDetails(
      summary: summary,
      members: memberRows.map(_mapMember).toList(growable: false),
      notes: notes,
    );
  }

  @override
  Future<void> setPreferredMember({
    required int groupId,
    required int fileId,
  }) async {
    await _db.transaction(() async {
      await _ensureGroupExists(groupId);
      await _ensureMemberExists(groupId: groupId, fileId: fileId);

      // Record the group-level preference.
      await (_db.update(
        _db.duplicateGroups,
      )..where((g) => g.id.equals(groupId))).write(
        DuplicateGroupsCompanion(
          preferredFileId: Value(fileId),
          updatedAt: Value(_nowIso()),
        ),
      );

      // Always un-hide the chosen member so classification queries can see it.
      await (_db.update(_db.duplicateGroupMembers)
            ..where((m) => m.duplicateGroupId.equals(groupId))
            ..where((m) => m.fileId.equals(fileId)))
          .write(
            const DuplicateGroupMembersCompanion(
              isHiddenFromSearch: Value(false),
            ),
          );

      // Sync document_files.is_preferred when the selected file qualifies as a
      // healthy source-original PDF, so classification sees the same preference
      // without joining duplicate_groups.
      final DocumentFile? qualified =
          await (_db.select(_db.documentFiles)..where(
                (f) =>
                    f.id.equals(fileId) &
                    f.fileRoleKey.equals('source_original') &
                    f.fileHealthKey.equals('healthy') &
                    f.extension.lower().equals('.pdf'),
              ))
              .getSingleOrNull();
      if (qualified != null) {
        await (_db.update(_db.documentFiles)..where(
              (f) =>
                  f.documentId.equals(qualified.documentId) &
                  f.fileRoleKey.equals('source_original'),
            ))
            .write(const DocumentFilesCompanion(isPreferred: Value(false)));
        await (_db.update(_db.documentFiles)..where((f) => f.id.equals(fileId)))
            .write(const DocumentFilesCompanion(isPreferred: Value(true)));
      }
    });
  }

  @override
  Future<void> setMemberHidden({
    required int groupId,
    required int fileId,
    required bool hidden,
  }) async {
    await _db.transaction(() async {
      await _ensureGroupExists(groupId);
      await _ensureMemberExists(groupId: groupId, fileId: fileId);
      await (_db.update(_db.duplicateGroupMembers)
            ..where((m) => m.duplicateGroupId.equals(groupId))
            ..where((m) => m.fileId.equals(fileId)))
          .write(
            DuplicateGroupMembersCompanion(isHiddenFromSearch: Value(hidden)),
          );
      await (_db.update(_db.duplicateGroups)
            ..where((g) => g.id.equals(groupId)))
          .write(DuplicateGroupsCompanion(updatedAt: Value(_nowIso())));
    });
  }

  @override
  Future<void> updateReview({
    required int groupId,
    required String statusKey,
    String? notes,
  }) async {
    const validStatuses = {'unreviewed', 'reviewed', 'archived_for_later'};
    if (!validStatuses.contains(statusKey)) {
      throw ArgumentError.value(statusKey, 'statusKey', 'invalid status');
    }
    final normalizedNotes = notes?.trim();
    await _db.transaction(() async {
      await _ensureGroupExists(groupId);
      await (_db.update(
        _db.duplicateGroups,
      )..where((g) => g.id.equals(groupId))).write(
        DuplicateGroupsCompanion(
          reviewStatusKey: Value(statusKey),
          notes: Value(
            normalizedNotes == null || normalizedNotes.isEmpty
                ? null
                : normalizedNotes,
          ),
          updatedAt: Value(_nowIso()),
        ),
      );
    });
  }

  DuplicateGroupSummary _mapSummary(QueryRow row) {
    return DuplicateGroupSummary(
      id: row.read<int>('id'),
      groupCode: row.read<String>('group_code'),
      sha256Hash: row.read<String>('sha256_hash'),
      reviewStatusKey: row.read<String>('review_status_key'),
      memberCount: row.read<int>('member_count'),
      displayName: row.readNullable<String>('display_name'),
      preferredFileId: row.readNullable<int>('preferred_file_id'),
      createdAt: row.read<String>('created_at'),
      updatedAt: row.read<String>('updated_at'),
    );
  }

  DuplicateGroupFileItem _mapMember(QueryRow row) {
    return DuplicateGroupFileItem(
      fileId: row.read<int>('file_id'),
      documentId: row.read<int>('document_id'),
      documentCode: row.readNullable<String>('document_code'),
      documentTitle: row.readNullable<String>('title'),
      fileName: row.read<String>('file_name'),
      absolutePath: row.read<String>('absolute_path'),
      fileRoleKey: row.read<String>('file_role_key'),
      fileHealthKey: row.read<String>('file_health_key'),
      fileSizeBytes: row.read<int>('file_size_bytes'),
      workflowStatusKey: row.read<String>('workflow_status_key'),
      isHiddenFromSearch: row.read<int>('is_hidden_from_search') != 0,
      isPreferred: row.read<int>('is_preferred') != 0,
      addedAt: row.read<String>('added_at'),
    );
  }

  Future<void> _ensureGroupExists(int groupId) async {
    final row =
        await (_db.selectOnly(_db.duplicateGroups)
              ..addColumns([_db.duplicateGroups.id])
              ..where(_db.duplicateGroups.id.equals(groupId)))
            .getSingleOrNull();
    if (row == null) {
      throw StateError('Duplicate group $groupId not found.');
    }
  }

  Future<void> _ensureMemberExists({
    required int groupId,
    required int fileId,
  }) async {
    final row =
        await (_db.selectOnly(_db.duplicateGroupMembers)
              ..addColumns([_db.duplicateGroupMembers.fileId])
              ..where(
                _db.duplicateGroupMembers.duplicateGroupId.equals(groupId),
              )
              ..where(_db.duplicateGroupMembers.fileId.equals(fileId)))
            .getSingleOrNull();
    if (row == null) {
      throw StateError(
        'File $fileId is not a member of duplicate group $groupId.',
      );
    }
  }

  String _nowIso() => DateTime.now().toUtc().toIso8601String();
}
