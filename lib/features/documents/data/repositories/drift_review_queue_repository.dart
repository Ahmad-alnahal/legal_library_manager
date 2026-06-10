import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/entities/review_queue_item.dart';
import '../../domain/entities/review_queue_query.dart';
import '../../domain/repositories/review_queue_repository.dart';

/// Drift-backed [ReviewQueueRepository].
///
/// Pages at the database level with LIMIT/OFFSET plus a separate filtered count,
/// so the full library is never loaded into memory. Ordering is fixed to
/// ascending document id: this is stable across calls (ids never change), makes
/// pagination deterministic, and gives "the next document in the queue" a
/// well-defined meaning after a document is classified and leaves the queue.
/// All Drift types are confined to this class.
class DriftReviewQueueRepository implements ReviewQueueRepository {
  DriftReviewQueueRepository(this._db);

  final AppDatabase _db;

  /// File-health keys that make an associated file reviewable. A document is
  /// only eligible for either review scope when it has at least one file in one
  /// of these states; documents with zero files or only broken files
  /// (`corrupted`, `unreadable`, `missing`) are excluded entirely. This is
  /// expressed as a correlated `EXISTS` subquery so the filtering happens in the
  /// database (it never loads the queue into memory) and so count/pagination
  /// stay accurate. Broken document/file records are not modified or hidden from
  /// any other (future) problem-file workflow.
  static const String _reviewableFileExists =
      "EXISTS (SELECT 1 FROM document_files df "
      "WHERE df.document_id = d.id "
      "AND df.file_health_key IN ('healthy', 'unknown'))";

  @override
  Future<ReviewQueuePage> getQueue(ReviewQueueQuery query) async {
    if (query.offset < 0 || query.limit < 1 || query.limit > 200) {
      throw ArgumentError('Pagination requires offset >= 0 and limit 1..200.');
    }

    final List<String> statuses = query.scope.statusKeys;
    final String placeholders = List.filled(statuses.length, '?').join(', ');
    final List<Variable<Object>> statusVars = [
      for (final s in statuses) Variable<String>(s),
    ];

    final countRow = await _db
        .customSelect(
          'SELECT COUNT(*) AS total FROM documents d '
          'WHERE d.workflow_status_key IN ($placeholders) '
          'AND $_reviewableFileExists',
          variables: statusVars,
          readsFrom: {_db.documents, _db.documentFiles},
        )
        .getSingle();
    final int total = countRow.read<int>('total');

    final rows = await _db
        .customSelect(
          '''
SELECT
  d.id,
  d.document_code,
  d.title,
  (
    SELECT df.file_name
    FROM document_files df
    WHERE df.document_id = d.id AND df.file_role_key = 'source_original'
    ORDER BY df.is_preferred DESC, df.id ASC
    LIMIT 1
  ) AS source_file_name,
  dt.name_ar AS document_type_name_ar,
  d.workflow_status_key,
  d.updated_at
FROM documents d
LEFT JOIN document_types dt ON dt.id = d.document_type_id
WHERE d.workflow_status_key IN ($placeholders)
  AND $_reviewableFileExists
ORDER BY d.id ASC
LIMIT ? OFFSET ?
''',
          variables: [
            ...statusVars,
            Variable<int>(query.limit),
            Variable<int>(query.offset),
          ],
          readsFrom: {_db.documents, _db.documentTypes, _db.documentFiles},
        )
        .get();

    return ReviewQueuePage(
      items: rows
          .map(
            (row) => ReviewQueueItem(
              id: row.read<int>('id'),
              documentCode: row.readNullable<String>('document_code'),
              title: row.readNullable<String>('title'),
              sourceFileName: row.readNullable<String>('source_file_name'),
              documentTypeNameAr: row.readNullable<String>(
                'document_type_name_ar',
              ),
              workflowStatusKey: row.read<String>('workflow_status_key'),
              updatedAt: row.read<String>('updated_at'),
            ),
          )
          .toList(growable: false),
      totalCount: total,
      offset: query.offset,
      limit: query.limit,
    );
  }
}
