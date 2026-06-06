import 'package:drift/drift.dart';
import 'package:drift/native.dart';

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

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      // Partial unique indexes that drift's annotation indexes cannot express
      // (they require a WHERE clause). Part of the initial schema creation.
      //
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
    },
    beforeOpen: (OpeningDetails details) async {
      // Enforce foreign keys on every connection open (file or in-memory).
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
