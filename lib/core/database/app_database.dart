import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../constants/domain_keys.dart';
import '../validation/category_name.dart';
import 'database_connection.dart';
import 'tables/account_security_state.dart';
import 'tables/accounts.dart';
import 'tables/book_details.dart';
import 'tables/court_case_details.dart';
import 'tables/document_classifications.dart';
import 'tables/document_files.dart';
import 'tables/document_keywords.dart';
import 'tables/document_types.dart';
import 'tables/documents.dart';
import 'tables/duplicate_group_members.dart';
import 'tables/duplicate_groups.dart';
import 'tables/export_batch_documents.dart';
import 'tables/export_batches.dart';
import 'tables/file_conversions.dart';
import 'tables/file_events.dart';
import 'tables/file_open_events.dart';
import 'tables/import_batch_files.dart';
import 'tables/import_batches.dart';
import 'tables/keywords.dart';
import 'tables/legislation_details.dart';
import 'tables/legislation_relations.dart';
import 'tables/main_categories.dart';
import 'tables/recovery_credentials.dart';
import 'tables/related_file_candidates.dart';
import 'tables/reference_tables.dart';
import 'tables/report_details.dart';
import 'tables/research_details.dart';
import 'tables/security_audit_log.dart';
import 'tables/settings.dart';
import 'tables/sub_categories.dart';
import 'tables/thesis_details.dart';

part 'app_database.g.dart';

/// The Drift database for MARJIY.
///
/// Defines the bilingual reference tables, the core `documents`/`document_files`
/// tables, the classification/keyword tables, the document-type detail tables,
/// the duplicate-group tables, the file-conversion tracking table, the
/// audit/import/settings tables, and the export tables. This completes the M2
/// schema from `database_schema_spec.md`.
@DriftDatabase(
  tables: [
    DocumentTypes,
    MainCategories,
    SubCategories,
    Languages,
    Countries,
    TrustLevels,
    UsageRights,
    MetadataQualities,
    WorkflowStatuses,
    FileRoles,
    FileHealthStatuses,
    Documents,
    DocumentFiles,
    DocumentClassifications,
    Keywords,
    DocumentKeywords,
    BookDetails,
    ThesisDetails,
    ResearchDetails,
    LegislationDetails,
    LegislationRelations,
    CourtCaseDetails,
    ReportDetails,
    DuplicateGroups,
    DuplicateGroupMembers,
    FileConversions,
    FileEvents,
    FileOpenEvents,
    ImportBatches,
    ImportBatchFiles,
    Settings,
    ExportBatches,
    ExportBatchDocuments,
    Accounts,
    AccountSecurityStates,
    RecoveryCredentials,
    RelatedFileCandidates,
    SecurityAuditLog,
  ],
)
class AppDatabase extends _$AppDatabase {
  /// Opens the production database backed by an on-disk SQLite file.
  AppDatabase() : super(openProductionConnection());

  /// Opens a database on the provided executor. Used by tests to inject an
  /// in-memory connection.
  AppDatabase.forExecutor(super.executor);

  /// Creates a throwaway in-memory database for tests.
  factory AppDatabase.inMemory() =>
      AppDatabase.forExecutor(NativeDatabase.memory());

  /// Schema version 9 adds `documents.language_other`, a free-text column for
  /// user-described languages when `language_key = 'other'`.
  ///
  /// Version 8 adds the `documents_fts` FTS5 virtual table, replacing
  /// the per-column LIKE search with a single indexed MATCH query.
  ///
  /// Version 7 adds `legislation_details.legislation_type_other` for
  /// typed custom labels when legislation_type_key is 'other'.
  ///
  /// Version 6 added the `legislation_relations` table and extended
  /// `legislation_details` with four new nullable columns plus expands the
  /// effective_status_key allowed values (Pre-P3 Slice A).
  ///
  /// Version 5 added `related_file_candidates` (P2.4).
  /// Version 4 added `paired_count` to `import_batches` (P2.1).
  /// Version 3 added the four security tables (M14).
  /// Version 2 added normalized category-name columns (M6.4).
  /// Version 1 databases are migrated through all steps in sequence.
  @override
  int get schemaVersion => 9;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await _createClassificationPartialIndexes();
      // A fresh database is created directly at version 2, so the normalized
      // category indexes are part of initial creation.
      await _createCategoryNormalizedIndexes();
      await _createLegislationRelationIndexes();
      await _createDocumentsFtsTable();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        await _migrateV1ToV2();
      }
      if (from < 3) {
        await _migrateV2ToV3(m);
      }
      if (from < 4) {
        await _migrateV3ToV4();
      }
      if (from < 5) {
        await _migrateV4ToV5(m);
      }
      if (from < 6) {
        await _migrateV5ToV6(m);
      }
      if (from < 7) {
        await _migrateV6ToV7();
      }
      if (from < 8) {
        await _migrateV7ToV8();
      }
      if (from < 9) {
        await _migrateV8ToV9();
      }
    },
    beforeOpen: (OpeningDetails details) async {
      // Enforce foreign keys on every connection open (file or in-memory).
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// Partial unique indexes that drift's annotation indexes cannot express
  /// (they require a WHERE clause). Part of the initial schema creation.
  Future<void> _createClassificationPartialIndexes() async {
    // One primary classification per document.
    await customStatement(
      'CREATE UNIQUE INDEX ux_document_classifications_primary '
      'ON document_classifications (document_id) '
      "WHERE classification_role_key = 'primary'",
    );
    // Unique (document, main, sub) combination when a subcategory is set.
    await customStatement(
      'CREATE UNIQUE INDEX ux_document_classifications_combo_sub '
      'ON document_classifications (document_id, main_category_id, '
      'sub_category_id) WHERE sub_category_id IS NOT NULL',
    );
    // Unique (document, main) combination when no subcategory is set
    // (SQLite treats NULLs as distinct, so this case needs its own index).
    await customStatement(
      'CREATE UNIQUE INDEX ux_document_classifications_combo_nosub '
      'ON document_classifications (document_id, main_category_id) '
      'WHERE sub_category_id IS NULL',
    );
  }

  /// The four unique indexes that enforce normalized category-name integrity:
  /// main-category Arabic/English names are globally unique; subcategory
  /// Arabic/English names are unique within their parent main category.
  Future<void> _createCategoryNormalizedIndexes() async {
    await customStatement(
      'CREATE UNIQUE INDEX ux_main_categories_normalized_name_ar '
      'ON main_categories (normalized_name_ar)',
    );
    await customStatement(
      'CREATE UNIQUE INDEX ux_main_categories_normalized_name_en '
      'ON main_categories (normalized_name_en)',
    );
    await customStatement(
      'CREATE UNIQUE INDEX ux_sub_categories_main_normalized_name_ar '
      'ON sub_categories (main_category_id, normalized_name_ar)',
    );
    await customStatement(
      'CREATE UNIQUE INDEX ux_sub_categories_main_normalized_name_en '
      'ON sub_categories (main_category_id, normalized_name_en)',
    );
  }

  /// Adds `paired_count` column to `import_batches` (P2.1).
  ///
  /// The column cannot be NOT NULL without a DEFAULT in SQLite — using
  /// `DEFAULT 0` satisfies the constraint and back-fills all existing rows
  /// automatically. The migration is skipped when `import_batches` does not
  /// exist (possible only in minimal test proxy databases that simulate a
  /// version number without the full schema; real installations always have the
  /// table from initial setup).
  Future<void> _migrateV3ToV4() async {
    final List<QueryRow> tables = await customSelect(
      "SELECT name FROM sqlite_master "
      "WHERE type='table' AND name='import_batches';",
    ).get();
    if (tables.isEmpty) return;
    await customStatement(
      'ALTER TABLE import_batches '
      'ADD COLUMN paired_count INTEGER NOT NULL DEFAULT 0',
    );
  }

  /// Adds the `related_file_candidates` table (P2.4).
  ///
  /// Safe for existing V4 databases: no existing rows are touched. The table is
  /// created fresh with all columns and constraints.
  Future<void> _migrateV4ToV5(Migrator m) async {
    await m.createTable(relatedFileCandidates);
  }

  /// Adds the four M14 security tables to a v2 database.
  ///
  /// Creates accounts, account_security_state, recovery_credentials, and
  /// security_audit_log. No existing data is touched. The migration is
  /// idempotent from the perspective of existing rows: it only adds tables.
  Future<void> _migrateV2ToV3(Migrator m) async {
    await m.createTable(accounts);
    await m.createTable(accountSecurityStates);
    await m.createTable(recoveryCredentials);
    await m.createTable(securityAuditLog);
  }

  /// Transactional v1 -> v2 migration.
  ///
  /// Adds the normalized columns, backfills every existing main/subcategory
  /// using the shared normalization, detects collisions the stronger
  /// normalization would create, and only then builds the unique indexes. If
  /// any collision is found the whole migration rolls back via the surrounding
  /// transaction, leaving the v1 database untouched (no partial columns,
  /// indexes, or data changes), and a safe diagnostic naming the colliding
  /// category ids/keys is thrown. No category is deleted, merged, renamed, or
  /// deactivated.
  Future<void> _migrateV1ToV2() async {
    await transaction(() async {
      // 1. Add the normalized columns. Existing rows take a temporary empty
      //    default; they are overwritten by the backfill below before any
      //    unique index is created.
      for (final String table in const ['main_categories', 'sub_categories']) {
        await customStatement(
          'ALTER TABLE $table ADD COLUMN normalized_name_ar TEXT NOT NULL '
          "DEFAULT ''",
        );
        await customStatement(
          'ALTER TABLE $table ADD COLUMN normalized_name_en TEXT NOT NULL '
          "DEFAULT ''",
        );
      }

      // 2. Backfill normalized values for every row (seeded and user-created),
      //    using the single shared normalization implementation.
      await _backfillNormalizedNames('main_categories');
      await _backfillNormalizedNames('sub_categories');

      // 3. Detect collisions before creating any unique index.
      final List<String> collisions = await _detectCategoryCollisions();
      if (collisions.isNotEmpty) {
        // Throwing rolls back the surrounding transaction (and the ALTERs).
        throw CategoryNormalizationCollisionException(collisions);
      }

      // 4. Only after a clean collision check, enforce uniqueness.
      await _createCategoryNormalizedIndexes();
    });
  }

  /// Creates performance indexes on `legislation_relations`.
  ///
  /// Called on both fresh database creation (onCreate) and during the v5→v6
  /// migration so indexes exist in all code paths.
  Future<void> _createLegislationRelationIndexes() async {
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_lr_source '
      'ON legislation_relations(source_document_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_lr_target '
      'ON legislation_relations(target_document_id)',
    );
    await customStatement(
      'CREATE INDEX IF NOT EXISTS idx_lr_type '
      'ON legislation_relations(relation_type_key)',
    );
  }

  /// Migrates a v5 database to v6 (Pre-P3 Slice A).
  ///
  /// 1. Recreates `legislation_details` via a temp table to add four nullable
  ///    columns and expand the effective_status_key CHECK constraint — SQLite
  ///    does not support modifying CHECK constraints via ALTER TABLE.
  /// 2. Creates the new `legislation_relations` table.
  /// 3. Creates performance indexes on `legislation_relations`.
  ///
  /// Existing `legislation_details` rows are preserved; the four new columns
  /// default to NULL. The migration runs inside the Drift-managed upgrade
  /// transaction.
  Future<void> _migrateV5ToV6(Migrator m) async {
    // Step A: recreate legislation_details with expanded schema.
    // Guard: skip if the table does not exist (possible only in minimal test
    // proxy databases that simulate a version number without the full schema;
    // real installations always have the table from initial setup).
    final List<QueryRow> existing = await customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' "
      "AND name='legislation_details';",
    ).get();
    if (existing.isNotEmpty) {
      await customStatement('''
        CREATE TABLE legislation_details_v6 (
          document_id INTEGER NOT NULL
            REFERENCES documents(id) ON DELETE CASCADE,
          legislation_type_key TEXT
            CHECK(legislation_type_key IN (
              'ordinary_legislation','regulation',
              'executive_regulation','other')),
          effective_status_key TEXT
            CHECK(effective_status_key IN (
              'active','repealed','amended','expired','unknown')),
          issue_number TEXT,
          publication_date TEXT,
          legislation_number TEXT,
          legislation_year INTEGER,
          effective_date TEXT,
          repeal_date TEXT,
          PRIMARY KEY (document_id)
        ) WITHOUT ROWID
      ''');
      await customStatement('''
        INSERT INTO legislation_details_v6
          (document_id, legislation_type_key, effective_status_key,
           issue_number, publication_date)
        SELECT
          document_id, legislation_type_key, effective_status_key,
          issue_number, publication_date
        FROM legislation_details
      ''');
      await customStatement('DROP TABLE legislation_details');
      await customStatement(
        'ALTER TABLE legislation_details_v6 RENAME TO legislation_details',
      );
    }

    // Step B: create legislation_relations table.
    await m.createTable(legislationRelations);

    // Step C: create performance indexes.
    await _createLegislationRelationIndexes();
  }

  /// Adds the custom free-text label for `legislation_type_key = 'other'`.
  ///
  /// This is nullable so existing v6 rows remain valid. The application/domain
  /// validation enforces that it is filled when a user chooses "other".
  Future<void> _migrateV6ToV7() async {
    final List<QueryRow> tables = await customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' "
      "AND name='legislation_details';",
    ).get();
    if (tables.isEmpty) return;

    final Set<String> columns = (await customSelect(
      'PRAGMA table_info(legislation_details);',
    ).get()).map((row) => row.read<String>('name')).toSet();
    if (columns.contains('legislation_type_other')) return;

    await customStatement(
      'ALTER TABLE legislation_details '
      'ADD COLUMN legislation_type_other TEXT',
    );
  }

  /// Creates the `documents_fts` FTS5 virtual table used for metadata search.
  ///
  /// Contentless (`content=''`) so the index carries its own copy of the
  /// aggregated text; rows are populated explicitly via
  /// [rebuildFtsIndex]/[updateDocumentFts] rather than SQLite triggers.
  ///
  /// `contentless_delete=1` is required for row deletion to actually work: a
  /// plain contentless table silently no-ops a `'delete'` command by rowid
  /// (verified against this project's bundled sqlite3 3.53.1 — the row stays
  /// matchable and a later re-insert with the same rowid duplicates terms
  /// instead of replacing them). With `contentless_delete=1`, a normal
  /// `DELETE FROM documents_fts WHERE rowid = ?` correctly removes the row.
  Future<void> _createDocumentsFtsTable() async {
    await customStatement('''
      CREATE VIRTUAL TABLE IF NOT EXISTS documents_fts
      USING fts5(
        title,
        document_code,
        summary,
        source_description,
        keywords,
        file_names,
        content='',
        contentless_delete=1,
        tokenize='unicode61 remove_diacritics 1'
      )
    ''');
  }

  /// Migrates a v7 database to v8 (P4): adds the `documents_fts` table and
  /// populates it from every existing document.
  ///
  /// The populate step is skipped when `documents` does not exist (possible
  /// only in minimal test proxy databases that simulate a version number
  /// without the full schema; real installations always have the table from
  /// initial setup).
  Future<void> _migrateV7ToV8() async {
    await _createDocumentsFtsTable();
    final List<QueryRow> tables = await customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='documents';",
    ).get();
    if (tables.isEmpty) return;
    await rebuildFtsIndex();
  }

  /// Rebuilds the entire FTS index from scratch.
  ///
  /// Deletes all existing FTS rows then re-inserts from the documents table.
  /// Called during v7->v8 migration and can be triggered manually for
  /// recovery.
  Future<void> rebuildFtsIndex() async {
    await customStatement("DELETE FROM documents_fts");
    await customStatement("""
      INSERT INTO documents_fts(rowid, title, document_code, summary,
        source_description, keywords, file_names)
      SELECT
        d.id,
        COALESCE(d.title, ''),
        COALESCE(d.document_code, ''),
        COALESCE(d.summary, ''),
        COALESCE(d.source_description, ''),
        COALESCE((
          SELECT GROUP_CONCAT(k.display_value, ' ')
          FROM document_keywords dk
          JOIN keywords k ON k.id = dk.keyword_id
          WHERE dk.document_id = d.id
        ), ''),
        COALESCE((
          SELECT GROUP_CONCAT(df.file_name, ' ')
          FROM document_files df
          WHERE df.document_id = d.id
            AND df.file_role_key = '${FileRoleKey.sourceOriginal}'
        ), '')
      FROM documents d
    """);
  }

  /// Updates (delete + re-insert) the FTS entry for a single document.
  ///
  /// Call this inside any repository transaction that modifies a document's
  /// title, summary, source_description, document_code, keywords, or file
  /// names.
  Future<void> updateDocumentFts(int documentId) async {
    await customStatement('DELETE FROM documents_fts WHERE rowid = ?', [
      documentId,
    ]);
    await customStatement(
      """
      INSERT INTO documents_fts(rowid, title, document_code, summary,
        source_description, keywords, file_names)
      SELECT
        d.id,
        COALESCE(d.title, ''),
        COALESCE(d.document_code, ''),
        COALESCE(d.summary, ''),
        COALESCE(d.source_description, ''),
        COALESCE((
          SELECT GROUP_CONCAT(k.display_value, ' ')
          FROM document_keywords dk
          JOIN keywords k ON k.id = dk.keyword_id
          WHERE dk.document_id = d.id
        ), ''),
        COALESCE((
          SELECT GROUP_CONCAT(df.file_name, ' ')
          FROM document_files df
          WHERE df.document_id = d.id
            AND df.file_role_key = '${FileRoleKey.sourceOriginal}'
        ), '')
      FROM documents d
      WHERE d.id = ?
    """,
      [documentId],
    );
  }

  /// Adds the free-text `language_other` column to `documents` (v9).
  ///
  /// Nullable — only populated when `language_key = 'other'`. Existing rows
  /// default to NULL. Guard skips if `documents` is absent (minimal test proxy).
  Future<void> _migrateV8ToV9() async {
    final List<QueryRow> tables = await customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='documents';",
    ).get();
    if (tables.isEmpty) return;

    final Set<String> cols = (await customSelect(
      'PRAGMA table_info(documents);',
    ).get()).map((r) => r.read<String>('name')).toSet();
    if (cols.contains('language_other')) return;

    await customStatement(
      'ALTER TABLE documents ADD COLUMN language_other TEXT',
    );
  }

  /// Reads each row's display names and writes back the shared normalized
  /// comparison values using parameterized statements (never string-built SQL).
  Future<void> _backfillNormalizedNames(String table) async {
    final List<QueryRow> rows = await customSelect(
      'SELECT id, name_ar, name_en FROM $table',
    ).get();
    for (final QueryRow row in rows) {
      final int id = row.read<int>('id');
      final String normalizedAr = normalizedCategoryNameAr(
        row.read<String>('name_ar'),
      );
      final String normalizedEn = normalizedCategoryNameEn(
        row.read<String>('name_en'),
      );
      await customStatement(
        'UPDATE $table SET normalized_name_ar = ?, normalized_name_en = ? '
        'WHERE id = ?',
        [normalizedAr, normalizedEn, id],
      );
    }
  }

  /// Returns one safe diagnostic string per detected collision, identifying
  /// only category ids/keys (never unrelated database content).
  Future<List<String>> _detectCategoryCollisions() async {
    final List<String> problems = [];
    problems.addAll(
      await _collisionsFor(
        scope: 'main_categories.normalized_name_ar',
        sql:
            'SELECT GROUP_CONCAT(id) AS ids, GROUP_CONCAT(key) AS keys '
            'FROM main_categories GROUP BY normalized_name_ar '
            'HAVING COUNT(*) > 1',
      ),
    );
    problems.addAll(
      await _collisionsFor(
        scope: 'main_categories.normalized_name_en',
        sql:
            'SELECT GROUP_CONCAT(id) AS ids, GROUP_CONCAT(key) AS keys '
            'FROM main_categories GROUP BY normalized_name_en '
            'HAVING COUNT(*) > 1',
      ),
    );
    problems.addAll(
      await _collisionsFor(
        scope: 'sub_categories(main_category_id, normalized_name_ar)',
        sql:
            'SELECT GROUP_CONCAT(id) AS ids, GROUP_CONCAT(key) AS keys '
            'FROM sub_categories GROUP BY main_category_id, normalized_name_ar '
            'HAVING COUNT(*) > 1',
      ),
    );
    problems.addAll(
      await _collisionsFor(
        scope: 'sub_categories(main_category_id, normalized_name_en)',
        sql:
            'SELECT GROUP_CONCAT(id) AS ids, GROUP_CONCAT(key) AS keys '
            'FROM sub_categories GROUP BY main_category_id, normalized_name_en '
            'HAVING COUNT(*) > 1',
      ),
    );
    return problems;
  }

  Future<List<String>> _collisionsFor({
    required String scope,
    required String sql,
  }) async {
    final List<QueryRow> rows = await customSelect(sql).get();
    return rows
        .map(
          (QueryRow r) =>
              '$scope -> ids=[${r.read<String>('ids')}] '
              'keys=[${r.read<String>('keys')}]',
        )
        .toList(growable: false);
  }
}

/// Thrown when the stronger v2 normalization would map two distinct existing
/// categories to the same normalized name. Carries only category ids/keys so a
/// diagnostic never exposes unrelated database content. The migration aborts and
/// rolls back, leaving the v1 database unchanged.
class CategoryNormalizationCollisionException implements Exception {
  const CategoryNormalizationCollisionException(this.collisions);

  /// One safe, id/key-only description per detected collision.
  final List<String> collisions;

  @override
  String toString() =>
      'CategoryNormalizationCollisionException: stronger category-name '
      'normalization would merge distinct categories; migration aborted and '
      'rolled back. Conflicts: ${collisions.join('; ')}';
}
