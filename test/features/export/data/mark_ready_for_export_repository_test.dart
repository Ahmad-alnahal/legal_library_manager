// test/features/export/data/mark_ready_for_export_repository_test.dart

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/database/seeding/reference_seeder.dart';
import 'package:legal_library_manager/features/documents/data/repositories/drift_document_metadata_repository.dart';
import 'package:legal_library_manager/features/export/domain/entities/export_eligibility_result.dart';

import '../../documents/support/document_test_support.dart';

void main() {
  late AppDatabase db;
  late DriftDocumentMetadataRepository repo;

  const now = '2026-07-18T12:00:00.000Z';

  setUp(() async {
    db = AppDatabase.inMemory();
    await ReferenceSeeder(db).seedAll();
    repo = DriftDocumentMetadataRepository(db);
  });

  tearDown(() => db.close());

  Future<int> addEligibleDocument({
    String workflowStatusKey = 'copied_to_library',
    String metadataQualityKey = 'high',
    String usageRightsKey = 'open_access',
    bool addHealthyManagedCopy = true,
  }) async {
    final int mainCategory = await mainId(db, 'public_law');
    final int id = await db
        .into(db.documents)
        .insert(
          DocumentsCompanion.insert(
            title: const Value('doc'),
            primaryMainCategoryId: Value(mainCategory),
            metadataQualityKey: Value(metadataQualityKey),
            usageRightsKey: Value(usageRightsKey),
            workflowStatusKey: Value(workflowStatusKey),
            createdAt: now,
            updatedAt: now,
          ),
        );
    if (addHealthyManagedCopy) {
      await addFile(db, id, role: 'managed_copy', health: 'healthy');
    }
    return id;
  }

  group('checkExportEligibility', () {
    test('a fully eligible document is reported eligible', () async {
      final id = await addEligibleDocument();
      final result = await repo.checkExportEligibility(id);
      expect(result, isA<ExportEligible>());
    });

    test('throws StateError for a missing document', () async {
      expect(
        () => repo.checkExportEligibility(999999),
        throwsA(isA<StateError>()),
      );
    });

    test('wrong workflow status is reported ineligible', () async {
      final id = await addEligibleDocument(workflowStatusKey: 'classified');
      final result = await repo.checkExportEligibility(id);
      expect(result, isA<ExportIneligible>());
      expect(
        (result as ExportIneligible).reasons,
        contains(
          'Document must be copied_to_library before it can be marked '
          'ready_for_export.',
        ),
      );
    });

    test('no healthy managed copy is reported ineligible', () async {
      final id = await addEligibleDocument(addHealthyManagedCopy: false);
      final result = await repo.checkExportEligibility(id);
      expect(
        (result as ExportIneligible).reasons,
        contains('Document has no healthy managed-copy file.'),
      );
    });

    test('inactive primary main category is reported ineligible', () async {
      final id = await addEligibleDocument();
      final mainCategoryId = await mainId(db, 'public_law');
      await (db.update(db.mainCategories)
            ..where((m) => m.id.equals(mainCategoryId)))
          .write(const MainCategoriesCompanion(isActive: Value(false)));

      final result = await repo.checkExportEligibility(id);
      expect(
        (result as ExportIneligible).reasons,
        contains('Document has no active primary classification.'),
      );
    });

    test('inactive primary subcategory is reported ineligible', () async {
      final mainCategory = await mainId(db, 'public_law');
      final subCategory = await subId(db, 'constitutional_law');
      final id = await db
          .into(db.documents)
          .insert(
            DocumentsCompanion.insert(
              title: const Value('doc'),
              primaryMainCategoryId: Value(mainCategory),
              primarySubCategoryId: Value(subCategory),
              metadataQualityKey: const Value('high'),
              usageRightsKey: const Value('open_access'),
              workflowStatusKey: const Value('copied_to_library'),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await addFile(db, id, role: 'managed_copy', health: 'healthy');
      await (db.update(db.subCategories)
            ..where((s) => s.id.equals(subCategory)))
          .write(const SubCategoriesCompanion(isActive: Value(false)));

      final result = await repo.checkExportEligibility(id);
      expect(
        (result as ExportIneligible).reasons,
        contains('Document primary subcategory is not active.'),
      );
    });

    test(
      'metadata quality below high/verified is reported ineligible',
      () async {
        final id = await addEligibleDocument(metadataQualityKey: 'medium');
        final result = await repo.checkExportEligibility(id);
        expect(
          (result as ExportIneligible).reasons,
          contains('Metadata quality must be high or verified.'),
        );
      },
    );

    test('unknown usage rights is reported ineligible', () async {
      final id = await addEligibleDocument(usageRightsKey: 'unknown');
      final result = await repo.checkExportEligibility(id);
      expect(
        (result as ExportIneligible).reasons,
        contains('Usage rights must be explicitly reviewed.'),
      );
    });
  });

  group('markReadyForExport', () {
    test('sets ready_for_export status and timestamp', () async {
      final id = await addEligibleDocument();
      final markAt = DateTime.utc(2026, 7, 18, 13, 30);

      await repo.markReadyForExport(id, now: markAt);

      final doc = await (db.select(
        db.documents,
      )..where((d) => d.id.equals(id))).getSingle();
      expect(doc.workflowStatusKey, 'ready_for_export');
      expect(doc.readyForExportAt, '2026-07-18T13:30:00.000Z');
      expect(doc.updatedAt, '2026-07-18T13:30:00.000Z');
    });

    test('throws StateError when the document is not copied_to_library '
        '(race condition)', () async {
      final id = await addEligibleDocument(
        workflowStatusKey: 'ready_for_export',
      );

      expect(
        () => repo.markReadyForExport(id, now: DateTime.utc(2026, 7, 18)),
        throwsA(isA<StateError>()),
      );

      final doc = await (db.select(
        db.documents,
      )..where((d) => d.id.equals(id))).getSingle();
      expect(doc.workflowStatusKey, 'ready_for_export');
    });

    test('throws StateError for a missing document', () async {
      expect(
        () => repo.markReadyForExport(999999, now: DateTime.utc(2026, 7, 18)),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('listReadyForExport', () {
    test('returns only ready_for_export documents ordered by '
        'ready_for_export_at ascending', () async {
      final earlier = await addEligibleDocument();
      await (db.update(db.documents)..where((d) => d.id.equals(earlier))).write(
        const DocumentsCompanion(
          documentCode: Value('DOC-0000001'),
          workflowStatusKey: Value('ready_for_export'),
          readyForExportAt: Value('2026-07-18T09:00:00.000Z'),
        ),
      );

      final later = await addEligibleDocument();
      await (db.update(db.documents)..where((d) => d.id.equals(later))).write(
        const DocumentsCompanion(
          documentCode: Value('DOC-0000002'),
          workflowStatusKey: Value('ready_for_export'),
          readyForExportAt: Value('2026-07-18T10:00:00.000Z'),
        ),
      );

      // Not ready_for_export: must be excluded.
      await addEligibleDocument(workflowStatusKey: 'copied_to_library');

      final refs = await repo.listReadyForExport();

      expect(refs.map((r) => r.id).toList(), [earlier, later]);
      expect(refs[0].documentCode, 'DOC-0000001');
      expect(refs[1].documentCode, 'DOC-0000002');
    });
  });
}
