import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../../features/categories/domain/services/category_name.dart';
import 'database_connection.dart';
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
import 'tables/main_categories.dart';
import 'tables/reference_tables.dart';
import 'tables/report_details.dart';
import 'tables/research_details.dart';
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

  /// Schema version 2 adds the internal normalized-name columns and the unique
  /// indexes that enforce category-name integrity (M6.4). Version 1 databases
  /// are migrated transactionally with a collision-safe backfill.
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await _createClassificationPartialIndexes();
      // A fresh database is created directly at version 2, so the normalized
      // category indexes are part of initial creation.
      await _createCategoryNormalizedIndexes();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        await _migrateV1ToV2();
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
