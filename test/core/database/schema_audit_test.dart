import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';

void main() {
  group('M2 schema audit', () {
    late AppDatabase db;
    const String nowIso = '2026-06-06T10:00:00Z';

    setUp(() {
      db = AppDatabase.inMemory();
    });

    tearDown(() async {
      await db.close();
    });

    Future<Set<String>> objectNames(String type) async =>
        (await db
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type = '$type';",
                )
                .get())
            .map((QueryRow r) => r.read<String>('name'))
            .toSet();

    // Every table required by database_schema_spec.md.
    const List<String> expectedTables = [
      // Reference (§5.3-5.5, §11.2)
      'document_types',
      'main_categories',
      'sub_categories',
      'languages',
      'countries',
      'trust_levels',
      'usage_rights',
      'metadata_qualities',
      'workflow_statuses',
      'file_roles',
      'file_health_statuses',
      // Core (§5.1-5.2)
      'documents',
      'document_files',
      // Classification / keywords (§5.6-5.8)
      'document_classifications',
      'keywords',
      'document_keywords',
      // Detail (§6)
      'book_details',
      'thesis_details',
      'research_details',
      'legislation_details',
      'court_case_details',
      'report_details',
      // Duplicates (§7)
      'duplicate_groups',
      'duplicate_group_members',
      // Conversion (§8)
      'file_conversions',
      // Audit / import (§9)
      'file_events',
      'file_open_events',
      'import_batches',
      'import_batch_files',
      // Settings (§11.1)
      'settings',
      // Export (§10)
      'export_batches',
      'export_batch_documents',
    ];

    // Every required named index (§12) plus the custom partial indexes.
    const List<String> expectedIndexes = [
      'ux_documents_document_code',
      'ix_documents_workflow_status_key',
      'ix_documents_document_type_id',
      'ix_documents_primary_main_category_id',
      'ix_documents_primary_sub_category_id',
      'ix_documents_publication_year',
      'ix_documents_country_key',
      'ix_documents_trust_level_key',
      'ix_documents_metadata_quality_key',
      'ix_documents_updated_at',
      'ux_document_files_absolute_path',
      'ix_document_files_document_id',
      'ix_document_files_sha256_hash',
      'ix_document_files_file_role_key',
      'ix_document_files_file_health_key',
      'ix_document_files_extension',
      'ix_document_classifications_document_id',
      'ix_document_classifications_main_sub',
      'ux_document_classifications_primary',
      'ux_document_classifications_combo_sub',
      'ux_document_classifications_combo_nosub',
      'ux_keywords_normalized_value',
      'ix_document_keywords_keyword_id',
      'ux_duplicate_groups_sha256_hash',
      'ix_duplicate_group_members_file_id',
      'ix_file_events_document_created',
      'ix_file_events_file_created',
      'ix_file_events_operation_id',
      'ix_file_open_events_file_created',
      'ix_import_batches_started_at',
      'ix_export_batches_created_at',
    ];

    test('all expected tables exist and bootstrap_info does not', () async {
      final Set<String> tables = await objectNames('table');
      for (final String t in expectedTables) {
        expect(tables, contains(t), reason: 'missing table $t');
      }
      expect(tables, isNot(contains('bootstrap_info')));
      expect(expectedTables.length, 32);
    });

    test('all required named indexes exist', () async {
      final Set<String> indexes = await objectNames('index');
      for (final String idx in expectedIndexes) {
        expect(indexes, contains(idx), reason: 'missing index $idx');
      }
    });

    test('partial classification indexes carry WHERE clauses', () async {
      final List<QueryRow> rows = await db
          .customSelect(
            "SELECT name, sql FROM sqlite_master WHERE type = 'index' "
            "AND name LIKE 'ux_document_classifications_%';",
          )
          .get();
      final Map<String, String> sqlByName = {
        for (final QueryRow r in rows)
          r.read<String>('name'): r.read<String>('sql'),
      };
      for (final String name in [
        'ux_document_classifications_primary',
        'ux_document_classifications_combo_sub',
        'ux_document_classifications_combo_nosub',
      ]) {
        expect(sqlByName[name], contains('WHERE'), reason: name);
      }
    });

    test('PRAGMA foreign_keys is enabled', () async {
      final QueryRow row = await db
          .customSelect('PRAGMA foreign_keys;')
          .getSingle();
      expect(row.read<int>('foreign_keys'), 1);
    });

    test('all six detail tables are WITHOUT ROWID', () async {
      const List<String> detailTables = [
        'book_details',
        'thesis_details',
        'research_details',
        'legislation_details',
        'court_case_details',
        'report_details',
      ];
      for (final String t in detailTables) {
        final QueryRow row = await db
            .customSelect(
              "SELECT sql FROM sqlite_master WHERE type = 'table' "
              "AND name = '$t';",
            )
            .getSingle();
        expect(
          row.read<String>('sql').toUpperCase(),
          contains('WITHOUT ROWID'),
          reason: '$t should be WITHOUT ROWID',
        );
      }
    });

    test('import batch row type is ImportBatch (no ImportBatche)', () async {
      final int id = await db
          .into(db.importBatches)
          .insert(
            ImportBatchesCompanion.insert(
              batchCode: 'AUDIT-1',
              sourceFolder: r'C:\src',
              recursiveScan: true,
              statusKey: 'running',
              startedAt: nowIso,
            ),
          );
      // Typed against the corrected data-class name.
      final ImportBatch batch = await (db.select(
        db.importBatches,
      )..where((b) => b.id.equals(id))).getSingle();
      expect(batch.batchCode, 'AUDIT-1');
      expect(batch.discoveredCount, 0);
    });
  });
}
