import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/entities/document_list_item.dart';
import '../../domain/entities/document_list_query.dart';
import '../../domain/repositories/document_list_repository.dart';

class DriftDocumentListRepository implements DocumentListRepository {
  DriftDocumentListRepository(this._db);

  final AppDatabase _db;

  @override
  Future<DocumentListPage> getDocuments(DocumentListQuery query) async {
    if (query.offset < 0 || query.limit < 1 || query.limit > 200) {
      throw ArgumentError('Pagination requires offset >= 0 and limit 1..200.');
    }
    final normalized = query.filters.normalized();
    final where = _buildWhere(normalized);
    final countRow = await _db
        .customSelect(
          'SELECT COUNT(*) AS total FROM documents d ${where.sql}',
          variables: where.variables,
          readsFrom: {_db.documents},
        )
        .getSingle();
    final total = countRow.read<int>('total');

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
  d.document_type_id,
  dt.name_ar AS document_type_name_ar,
  d.primary_main_category_id,
  mc.name_ar AS main_category_name_ar,
  d.primary_sub_category_id,
  sc.name_ar AS sub_category_name_ar,
  d.language_key,
  d.country_key,
  d.publication_year,
  d.workflow_status_key,
  d.trust_level_key,
  d.metadata_quality_key,
  d.updated_at,
  (SELECT COUNT(*) FROM document_files df WHERE df.document_id = d.id)
    AS file_count,
  EXISTS(
    SELECT 1
    FROM document_files df
    JOIN duplicate_group_members dgm ON dgm.file_id = df.id
    WHERE df.document_id = d.id AND dgm.is_hidden_from_search = 0
  ) AS has_duplicate,
  EXISTS(
    SELECT 1 FROM document_files df
    WHERE df.document_id = d.id AND df.file_health_key = 'corrupted'
  ) AS has_corrupted_file,
  EXISTS(
    SELECT 1 FROM document_files df
    WHERE df.document_id = d.id
      AND df.file_health_key IN ('unreadable', 'missing')
  ) AS has_unreadable_file
FROM documents d
LEFT JOIN document_types dt ON dt.id = d.document_type_id
LEFT JOIN main_categories mc ON mc.id = d.primary_main_category_id
LEFT JOIN sub_categories sc ON sc.id = d.primary_sub_category_id
${where.sql}
ORDER BY ${_orderBy(query.sort)}
LIMIT ? OFFSET ?
''',
          variables: [
            ...where.variables,
            Variable<int>(query.limit),
            Variable<int>(query.offset),
          ],
          readsFrom: {
            _db.documents,
            _db.documentTypes,
            _db.mainCategories,
            _db.subCategories,
            _db.documentFiles,
            _db.duplicateGroupMembers,
          },
        )
        .get();

    return DocumentListPage(
      items: rows.map(_mapItem).toList(growable: false),
      totalCount: total,
      offset: query.offset,
      limit: query.limit,
    );
  }

  @override
  Future<List<DocumentSourceFileItem>> getSourceFiles(int documentId) async {
    final rows =
        await (_db.select(_db.documentFiles)
              ..where(
                (f) =>
                    f.documentId.equals(documentId) &
                    f.fileRoleKey.equals('source_original'),
              )
              ..orderBy([
                (f) => OrderingTerm(
                  expression: f.isPreferred,
                  mode: OrderingMode.desc,
                ),
                (f) => OrderingTerm(expression: f.fileName),
                (f) => OrderingTerm(expression: f.id),
              ]))
            .get();
    return rows
        .map(
          (row) => DocumentSourceFileItem(
            id: row.id,
            fileName: row.fileName,
            absolutePath: row.absolutePath,
            fileRoleKey: row.fileRoleKey,
            fileHealthKey: row.fileHealthKey,
            fileSizeBytes: row.fileSizeBytes,
            isReadOnlySource: row.isReadOnlySource,
            isPreferred: row.isPreferred,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> setPreferredSourceFile(int documentId, int fileId) {
    return _db.transaction(() async {
      final selected =
          await (_db.select(_db.documentFiles)..where(
                (f) =>
                    f.id.equals(fileId) &
                    f.documentId.equals(documentId) &
                    f.fileRoleKey.equals('source_original') &
                    f.fileHealthKey.equals('healthy') &
                    f.extension.lower().equals('.pdf'),
              ))
              .getSingleOrNull();
      if (selected == null) {
        throw StateError('Preferred source must be a healthy source PDF.');
      }

      await (_db.update(_db.documentFiles)..where(
            (f) =>
                f.documentId.equals(documentId) &
                f.fileRoleKey.equals('source_original'),
          ))
          .write(const DocumentFilesCompanion(isPreferred: Value(false)));
      await (_db.update(_db.documentFiles)..where((f) => f.id.equals(fileId)))
          .write(const DocumentFilesCompanion(isPreferred: Value(true)));
    });
  }

  _Where _buildWhere(DocumentListFilters filters) {
    final clauses = <String>[];
    final variables = <Variable<Object>>[];

    void textEquals(String column, String? value) {
      if (value == null) return;
      clauses.add('$column = ?');
      variables.add(Variable<String>(value));
    }

    void intEquals(String column, int? value) {
      if (value == null) return;
      clauses.add('$column = ?');
      variables.add(Variable<int>(value));
    }

    textEquals('d.workflow_status_key', filters.workflowStatusKey);
    intEquals('d.document_type_id', filters.documentTypeId);
    intEquals('d.primary_main_category_id', filters.mainCategoryId);
    intEquals('d.primary_sub_category_id', filters.subCategoryId);
    textEquals('d.country_key', filters.countryKey);
    textEquals('d.language_key', filters.languageKey);
    textEquals('d.trust_level_key', filters.trustLevelKey);

    if (filters.fileHealthKey != null) {
      clauses.add('''
EXISTS(
  SELECT 1 FROM document_files df
  WHERE df.document_id = d.id AND df.file_health_key = ?
)''');
      variables.add(Variable<String>(filters.fileHealthKey!));
    }

    switch (filters.duplicateFilter) {
      case DuplicateFilter.any:
        break;
      case DuplicateFilter.duplicatesOnly:
        clauses.add(_duplicateExists);
      case DuplicateFilter.withoutDuplicates:
        clauses.add('NOT $_duplicateExists');
    }

    final search = filters.search;
    if (search != null) {
      final pattern = '%${_escapeLike(search)}%';
      clauses.add('''
(
  d.title LIKE ? ESCAPE '\\'
  OR d.document_code LIKE ? ESCAPE '\\'
  OR d.summary LIKE ? ESCAPE '\\'
  OR d.source_description LIKE ? ESCAPE '\\'
  OR EXISTS(
    SELECT 1
    FROM document_keywords dk
    JOIN keywords k ON k.id = dk.keyword_id
    WHERE dk.document_id = d.id
      AND (k.display_value LIKE ? ESCAPE '\\'
        OR k.normalized_value LIKE ? ESCAPE '\\')
  )
  OR EXISTS(
    SELECT 1 FROM document_files df
    WHERE df.document_id = d.id
      AND (df.file_name LIKE ? ESCAPE '\\'
        OR df.absolute_path LIKE ? ESCAPE '\\')
  )
)''');
      for (var i = 0; i < 8; i++) {
        variables.add(Variable<String>(pattern));
      }
    }

    return _Where(
      clauses.isEmpty ? '' : 'WHERE ${clauses.join(' AND ')}',
      variables,
    );
  }

  DocumentListItem _mapItem(QueryRow row) {
    return DocumentListItem(
      id: row.read<int>('id'),
      documentCode: row.readNullable<String>('document_code'),
      title: row.readNullable<String>('title'),
      sourceFileName: row.readNullable<String>('source_file_name'),
      documentTypeId: row.readNullable<int>('document_type_id'),
      documentTypeNameAr: row.readNullable<String>('document_type_name_ar'),
      primaryMainCategoryId: row.readNullable<int>('primary_main_category_id'),
      primaryMainCategoryNameAr: row.readNullable<String>(
        'main_category_name_ar',
      ),
      primarySubCategoryId: row.readNullable<int>('primary_sub_category_id'),
      primarySubCategoryNameAr: row.readNullable<String>(
        'sub_category_name_ar',
      ),
      languageKey: row.readNullable<String>('language_key'),
      countryKey: row.readNullable<String>('country_key'),
      publicationYear: row.readNullable<int>('publication_year'),
      workflowStatusKey: row.read<String>('workflow_status_key'),
      trustLevelKey: row.read<String>('trust_level_key'),
      metadataQualityKey: row.read<String>('metadata_quality_key'),
      fileCount: row.read<int>('file_count'),
      hasDuplicate: row.read<int>('has_duplicate') == 1,
      hasCorruptedFile: row.read<int>('has_corrupted_file') == 1,
      hasUnreadableFile: row.read<int>('has_unreadable_file') == 1,
      updatedAt: row.read<String>('updated_at'),
    );
  }

  String _orderBy(DocumentListSort sort) {
    return switch (sort) {
      DocumentListSort.updatedNewest => 'd.updated_at DESC, d.id DESC',
      DocumentListSort.updatedOldest => 'd.updated_at ASC, d.id ASC',
      DocumentListSort.titleAscending =>
        'd.title IS NULL, d.title COLLATE NOCASE ASC, d.id ASC',
      DocumentListSort.titleDescending =>
        'd.title IS NULL, d.title COLLATE NOCASE DESC, d.id DESC',
      DocumentListSort.publicationYearNewest =>
        'd.publication_year IS NULL, d.publication_year DESC, d.id DESC',
      DocumentListSort.publicationYearOldest =>
        'd.publication_year IS NULL, d.publication_year ASC, d.id ASC',
    };
  }

  String _escapeLike(String value) => value
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');

  static const String _duplicateExists = '''
EXISTS(
  SELECT 1
  FROM document_files df
  JOIN duplicate_group_members dgm ON dgm.file_id = df.id
  WHERE df.document_id = d.id AND dgm.is_hidden_from_search = 0
)''';
}

class _Where {
  const _Where(this.sql, this.variables);

  final String sql;
  final List<Variable<Object>> variables;
}
