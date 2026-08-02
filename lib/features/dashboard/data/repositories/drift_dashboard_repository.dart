// lib/features/dashboard/data/repositories/drift_dashboard_repository.dart

import 'package:drift/drift.dart';

import '../../../../core/constants/domain_keys.dart';
import '../../../../core/database/app_database.dart';
import '../../domain/entities/activity_source.dart';
import '../../domain/entities/dashboard_activity_item.dart';
import '../../domain/entities/dashboard_metrics.dart';
import '../../domain/repositories/dashboard_repository.dart';

/// Drift-backed read-only implementation of [DashboardRepository].
///
/// All metric definitions follow the exact counts specified in the M10.1 prompt:
///   - totalImportedFiles : document_files WHERE file_role_key = 'source_original'
///   - needsReview        : documents WHERE workflow_status_key = 'needs_review'
///   - inProgress         : documents WHERE workflow_status_key = 'in_progress'
///   - classified         : documents WHERE workflow_status_key = 'classified'
///   - copiedToLibrary    : documents WHERE workflow_status_key = 'copied_to_library'
///   - readyForExport     : documents WHERE workflow_status_key = 'ready_for_export'
///   - duplicateGroups    : duplicate_groups with >= 2 duplicate_group_members
///   - corruptedFiles     : document_files WHERE file_health_key = 'corrupted'
///   - totalDocuments     : COUNT(*) FROM documents
///
/// No write operations are performed. The implementation never mutates
/// documents, files, settings, roots, backups, or audit records.
class DriftDashboardRepository implements DashboardRepository {
  DriftDashboardRepository(this._db);

  final AppDatabase _db;

  @override
  Future<DashboardMetrics> getMetrics() async {
    final row = await _db
        .customSelect(
          '''
SELECT
  (SELECT COUNT(*) FROM document_files
    WHERE file_role_key = '${FileRoleKey.sourceOriginal}')        AS total_imported_files,
  (SELECT COUNT(*) FROM documents
    WHERE workflow_status_key = '${WorkflowStatusKey.needsReview}')     AS needs_review,
  (SELECT COUNT(*) FROM documents
    WHERE workflow_status_key = '${WorkflowStatusKey.inProgress}')      AS in_progress,
  (SELECT COUNT(*) FROM documents
    WHERE workflow_status_key = '${WorkflowStatusKey.classified}')       AS classified,
  (SELECT COUNT(*) FROM documents
    WHERE workflow_status_key = '${WorkflowStatusKey.copiedToLibrary}') AS copied_to_library,
  (SELECT COUNT(*) FROM documents
    WHERE workflow_status_key = '${WorkflowStatusKey.readyForExport}') AS ready_for_export,
  (SELECT COUNT(*) FROM documents)                  AS total_documents,
  (SELECT COUNT(*) FROM document_files
    WHERE file_health_key = '${FileHealthKey.corrupted}')            AS corrupted_files,
  (SELECT COUNT(*)
    FROM (
      SELECT dg.id
      FROM duplicate_groups dg
      JOIN duplicate_group_members dgm
        ON dgm.duplicate_group_id = dg.id
      GROUP BY dg.id
      HAVING COUNT(dgm.file_id) >= 2
    )
  )                                                 AS duplicate_groups
''',
          readsFrom: {
            _db.documentFiles,
            _db.documents,
            _db.duplicateGroups,
            _db.duplicateGroupMembers,
          },
        )
        .getSingle();

    return DashboardMetrics(
      totalImportedFiles: row.read<int>('total_imported_files'),
      needsReview: row.read<int>('needs_review'),
      inProgress: row.read<int>('in_progress'),
      classified: row.read<int>('classified'),
      copiedToLibrary: row.read<int>('copied_to_library'),
      readyForExport: row.read<int>('ready_for_export'),
      duplicateGroups: row.read<int>('duplicate_groups'),
      corruptedFiles: row.read<int>('corrupted_files'),
      totalDocuments: row.read<int>('total_documents'),
    );
  }

  @override
  Future<List<DashboardActivityItem>> getRecentActivity({
    int limit = 20,
  }) async {
    if (limit < 1 || limit > 200) {
      throw ArgumentError.value(limit, 'limit', 'must be between 1 and 200');
    }

    final rows = await _db
        .customSelect(
          '''
SELECT
  'file_event'   AS source,
  event_type_key AS event_key,
  document_id,
  file_id,
  NULL           AS batch_code,
  result_key,
  created_at
FROM file_events

UNION ALL

SELECT
  'file_open_event' AS source,
  open_target_key   AS event_key,
  document_id,
  file_id,
  NULL              AS batch_code,
  result_key,
  created_at
FROM file_open_events

UNION ALL

SELECT
  'import_batch' AS source,
  'import_batch' AS event_key,
  NULL           AS document_id,
  NULL           AS file_id,
  batch_code,
  status_key     AS result_key,
  started_at     AS created_at
FROM import_batches

ORDER BY created_at DESC
LIMIT ?
''',
          variables: [Variable.withInt(limit)],
          readsFrom: {_db.fileEvents, _db.fileOpenEvents, _db.importBatches},
        )
        .get();

    return rows
        .map((row) {
          final source = _parseSource(row.read<String>('source'));
          final ts = row.read<String>('created_at');
          return DashboardActivityItem(
            source: source,
            eventKey: row.read<String>('event_key'),
            documentId: row.readNullable<int>('document_id'),
            fileId: row.readNullable<int>('file_id'),
            batchCode: row.readNullable<String>('batch_code'),
            resultKey: row.readNullable<String>('result_key'),
            timestamp:
                DateTime.tryParse(ts) ?? DateTime.fromMillisecondsSinceEpoch(0),
          );
        })
        .toList(growable: false);
  }

  static ActivitySource _parseSource(String s) {
    return switch (s) {
      'file_open_event' => ActivitySource.fileOpenEvent,
      'import_batch' => ActivitySource.importBatch,
      _ => ActivitySource.fileEvent,
    };
  }
}
