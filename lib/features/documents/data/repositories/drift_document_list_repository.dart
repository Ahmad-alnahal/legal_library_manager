import 'package:drift/drift.dart';

import '../../../../core/constants/domain_keys.dart';
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
    SELECT src.file_name
    FROM document_files src
    WHERE src.document_id = d.id
      AND src.file_role_key = '${FileRoleKey.sourceOriginal}'
      AND NOT EXISTS (
        SELECT 1 FROM duplicate_group_members h
        WHERE h.file_id = src.id AND h.is_hidden_from_search = 1
      )
    ORDER BY src.is_preferred DESC,
      CASE WHEN EXISTS (
        SELECT 1
        FROM duplicate_groups grp
        JOIN duplicate_group_members mem
          ON mem.duplicate_group_id = grp.id
        WHERE mem.file_id = src.id
          AND grp.preferred_file_id = src.id
      ) THEN 0 ELSE 1 END ASC,
      src.id ASC
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
    WHERE df.document_id = d.id AND df.file_health_key = '${FileHealthKey.corrupted}'
  ) AS has_corrupted_file,
  EXISTS(
    SELECT 1 FROM document_files df
    WHERE df.document_id = d.id
      AND df.file_health_key IN ('${FileHealthKey.unreadable}', '${FileHealthKey.missing}')
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
            _db.duplicateGroups,
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
    final rows = await _db
        .customSelect(
          '''
SELECT
  df.id,
  df.file_name,
  df.absolute_path,
  df.file_role_key,
  df.file_health_key,
  df.file_size_bytes,
  df.is_read_only_source,
  df.is_preferred
FROM document_files df
WHERE df.document_id = ?
  AND df.file_role_key = '${FileRoleKey.sourceOriginal}'
  AND NOT EXISTS (
    SELECT 1
    FROM duplicate_group_members dgm
    WHERE dgm.file_id = df.id
      AND dgm.is_hidden_from_search = 1
  )
ORDER BY df.is_preferred DESC,
  CASE WHEN EXISTS (
    SELECT 1
    FROM duplicate_groups dg
    JOIN duplicate_group_members dgm2
      ON dgm2.duplicate_group_id = dg.id
    WHERE dgm2.file_id = df.id
      AND dg.preferred_file_id = df.id
  ) THEN 0 ELSE 1 END ASC,
  df.file_name ASC, df.id ASC
''',
          variables: [Variable<int>(documentId)],
          readsFrom: {
            _db.documentFiles,
            _db.duplicateGroups,
            _db.duplicateGroupMembers,
          },
        )
        .get();
    return rows
        .map(
          (row) => DocumentSourceFileItem(
            id: row.read<int>('id'),
            fileName: row.read<String>('file_name'),
            absolutePath: row.read<String>('absolute_path'),
            fileRoleKey: row.read<String>('file_role_key'),
            fileHealthKey: row.read<String>('file_health_key'),
            fileSizeBytes: row.read<int>('file_size_bytes'),
            isReadOnlySource: row.read<int>('is_read_only_source') == 1,
            isPreferred: row.read<int>('is_preferred') == 1,
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
                    f.fileRoleKey.equals(FileRoleKey.sourceOriginal) &
                    f.fileHealthKey.equals(FileHealthKey.healthy) &
                    f.extension.lower().equals('.pdf'),
              ))
              .getSingleOrNull();
      if (selected == null) {
        throw StateError('Preferred source must be a healthy source PDF.');
      }

      await (_db.update(_db.documentFiles)..where(
            (f) =>
                f.documentId.equals(documentId) &
                f.fileRoleKey.equals(FileRoleKey.sourceOriginal),
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
      final matchExpr = _buildFtsMatchExpression(search);
      if (matchExpr != null) {
        clauses.add(
          'd.id IN (SELECT rowid FROM documents_fts WHERE documents_fts MATCH ?)',
        );
        variables.add(Variable<String>(matchExpr));
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

  /// Converts a user search string into an FTS5 MATCH expression.
  ///
  /// Returns null when the input has no usable tokens (empty after
  /// stripping). Each whitespace-separated token becomes a prefix term
  /// (token*). All tokens must match (AND semantics). Special FTS5
  /// characters are stripped to prevent syntax errors.
  String? _buildFtsMatchExpression(String query) {
    final clean = query.replaceAll(RegExp(r'["\(\)\*\^\-]'), ' ');
    final tokens = clean
        .trim()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty);
    if (tokens.isEmpty) return null;
    return tokens.map((t) => '$t*').join(' AND ');
  }

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
