// test/features/export/data/export_metadata_repository_test.dart

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/constants/domain_keys.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/database/seeding/reference_seeder.dart';
import 'package:legal_library_manager/features/documents/data/repositories/drift_document_metadata_repository.dart';

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

  Future<int> addBaseDocument({
    required String documentCode,
    required String typeKey,
    String usageRightsKey = UsageRightsKey.openAccess,
    String? summary = 'ملخص',
  }) async {
    final mainCategory = await mainId(db, 'public_law');
    final subCategory = await subId(db, 'constitutional_law');
    final type = await typeId(db, typeKey);
    return db
        .into(db.documents)
        .insert(
          DocumentsCompanion.insert(
            documentCode: Value(documentCode),
            documentTypeId: Value(type),
            title: const Value('عنوان الوثيقة'),
            primaryMainCategoryId: Value(mainCategory),
            primarySubCategoryId: Value(subCategory),
            languageKey: const Value('ar'),
            countryKey: const Value('ps'),
            trustLevelKey: const Value(TrustLevelKey.trusted),
            usageRightsKey: Value(usageRightsKey),
            metadataQualityKey: const Value(MetadataQualityKey.high),
            summary: Value(summary),
            workflowStatusKey: const Value(WorkflowStatusKey.readyForExport),
            readyForExportAt: const Value(now),
            createdAt: now,
            updatedAt: now,
          ),
        );
  }

  group('loadExportMetadata', () {
    test('returns correct fields for a non-legislation document', () async {
      final id = await addBaseDocument(
        documentCode: 'DOC-0000001',
        typeKey: 'book',
      );

      final result = await repo.loadExportMetadata([id]);

      expect(result, hasLength(1));
      final m = result.single;
      expect(m.documentCode, 'DOC-0000001');
      expect(m.titleAr, 'عنوان الوثيقة');
      expect(m.titleEn, isNull);
      expect(m.documentTypeKey, 'book');
      expect(m.primaryMainCategoryKey, 'public_law');
      expect(m.primarySubcategoryKey, 'constitutional_law');
      expect(m.countryCode, 'ps');
      expect(m.languageKey, 'ar');
      expect(m.trustLevelKey, TrustLevelKey.trusted);
      expect(m.usageRightsKey, UsageRightsKey.openAccess);
      expect(m.isUsageRightsFlagged, isFalse);
      expect(m.metadataQualityKey, MetadataQualityKey.high);
      expect(m.summaryAr, 'ملخص');
      expect(m.legislationDetails, isNull);
      expect(m.legislationRelations, isEmpty);
    });

    test('returns correct fields including details and relations for a '
        'legislation document', () async {
      final target = await addBaseDocument(
        documentCode: 'DOC-0000002',
        typeKey: 'legislation',
      );
      final id = await addBaseDocument(
        documentCode: 'DOC-0000001',
        typeKey: 'legislation',
      );

      await db
          .into(db.legislationDetails)
          .insert(
            LegislationDetailsCompanion.insert(
              documentId: id,
              legislationTypeKey: const Value('ordinary_legislation'),
              effectiveStatusKey: const Value('active'),
              legislationNumber: const Value('12'),
              legislationYear: const Value(2020),
              effectiveDate: const Value('2020-01-01'),
              repealDate: const Value(null),
            ),
          );

      await db
          .into(db.legislationRelations)
          .insert(
            LegislationRelationsCompanion.insert(
              sourceDocumentId: id,
              targetDocumentId: target,
              relationTypeKey: 'amends',
              relationScopeKey: const Value('partial'),
              effectiveDate: const Value('2021-01-01'),
              notes: const Value('ملاحظة'),
              createdAt: now,
              updatedAt: now,
            ),
          );

      final result = await repo.loadExportMetadata([id]);

      expect(result, hasLength(1));
      final m = result.single;
      expect(m.documentTypeKey, 'legislation');
      expect(m.legislationDetails, isNotNull);
      expect(m.legislationDetails!.legislationNumber, '12');
      expect(m.legislationDetails!.legislationYear, '2020');
      expect(m.legislationDetails!.effectiveDate, '2020-01-01');
      expect(m.legislationDetails!.repealDate, isNull);
      expect(m.legislationDetails!.effectiveStatusKey, 'active');
      expect(m.legislationDetails!.legislationTypeKey, 'ordinary_legislation');

      expect(m.legislationRelations, hasLength(1));
      final relation = m.legislationRelations.single;
      expect(relation.targetDocumentCode, 'DOC-0000002');
      expect(relation.relationTypeKey, 'amends');
      expect(relation.scope, 'partial');
      expect(relation.effectiveDate, '2021-01-01');
      expect(relation.notes, 'ملاحظة');
    });

    test('isUsageRightsFlagged is true for personal_use_only and '
        'permission_required', () async {
      final personal = await addBaseDocument(
        documentCode: 'DOC-0000003',
        typeKey: 'book',
        usageRightsKey: UsageRightsKey.personalUseOnly,
      );
      final permission = await addBaseDocument(
        documentCode: 'DOC-0000004',
        typeKey: 'book',
        usageRightsKey: UsageRightsKey.permissionRequired,
      );
      final open = await addBaseDocument(
        documentCode: 'DOC-0000005',
        typeKey: 'book',
        usageRightsKey: UsageRightsKey.openAccess,
      );

      final result = await repo.loadExportMetadata([
        personal,
        permission,
        open,
      ]);

      final byCode = {for (final m in result) m.documentCode: m};
      expect(byCode['DOC-0000003']!.isUsageRightsFlagged, isTrue);
      expect(byCode['DOC-0000004']!.isUsageRightsFlagged, isTrue);
      expect(byCode['DOC-0000005']!.isUsageRightsFlagged, isFalse);
    });

    test('never returns local paths or the integer document id', () async {
      final id = await addBaseDocument(
        documentCode: 'DOC-0000006',
        typeKey: 'book',
      );
      await addFile(
        db,
        id,
        role: FileRoleKey.managedCopy,
        health: FileHealthKey.healthy,
      );

      final result = await repo.loadExportMetadata([id]);
      final m = result.single;

      expect(m.toString(), isNot(contains('C:\\')));
      expect(m.toString(), isNot(contains('$id,')));
    });

    test('result order matches the order of documentIds', () async {
      final first = await addBaseDocument(
        documentCode: 'DOC-0000007',
        typeKey: 'book',
      );
      final second = await addBaseDocument(
        documentCode: 'DOC-0000008',
        typeKey: 'book',
      );

      final result = await repo.loadExportMetadata([second, first]);
      expect(result.map((m) => m.documentCode).toList(), [
        'DOC-0000008',
        'DOC-0000007',
      ]);
    });
  });

  group('loadExportCategories', () {
    test('returns only active categories ordered by sort_order with nested '
        'subcategories', () async {
      final inactiveMain = await mainId(db, 'islamic_jurisprudence');
      await (db.update(db.mainCategories)
            ..where((m) => m.id.equals(inactiveMain)))
          .write(const MainCategoriesCompanion(isActive: Value(false)));

      final result = await repo.loadExportCategories();

      expect(
        result.any((c) => c.mainCategoryKey == 'islamic_jurisprudence'),
        isFalse,
      );
      final keys = result.map((c) => c.mainCategoryKey).toList();
      final publicLaw = result.firstWhere(
        (c) => c.mainCategoryKey == 'public_law',
      );
      expect(publicLaw.subcategories, isNotEmpty);
      expect(
        publicLaw.subcategories.any(
          (s) => s.subcategoryKey == 'constitutional_law',
        ),
        isTrue,
      );
      // Sorted ascending by sort_order.
      for (var i = 1; i < result.length; i++) {
        expect(
          result[i].sortOrder,
          greaterThanOrEqualTo(result[i - 1].sortOrder),
        );
      }
      expect(keys, isNot(contains('islamic_jurisprudence')));
    });

    test('excludes inactive subcategories', () async {
      final subCategory = await subId(db, 'human_rights');
      await (db.update(db.subCategories)
            ..where((s) => s.id.equals(subCategory)))
          .write(const SubCategoriesCompanion(isActive: Value(false)));

      final result = await repo.loadExportCategories();
      final publicLaw = result.firstWhere(
        (c) => c.mainCategoryKey == 'public_law',
      );
      expect(
        publicLaw.subcategories.any((s) => s.subcategoryKey == 'human_rights'),
        isFalse,
      );
    });
  });

  group('loadExportKeywords', () {
    Future<int> addKeyword(String value) => db
        .into(db.keywords)
        .insert(
          KeywordsCompanion.insert(
            normalizedValue: value,
            displayValue: value,
            createdAt: now,
          ),
        );

    Future<void> linkKeyword(int docId, int keywordId) => db
        .into(db.documentKeywords)
        .insert(
          DocumentKeywordsCompanion.insert(
            documentId: docId,
            keywordId: keywordId,
            createdAt: now,
          ),
        );

    test('returns only keywords for the given document ids', () async {
      final included = await addBaseDocument(
        documentCode: 'DOC-0000010',
        typeKey: 'book',
      );
      final excluded = await addBaseDocument(
        documentCode: 'DOC-0000011',
        typeKey: 'book',
      );
      final kw1 = await addKeyword('عقود');
      final kw2 = await addKeyword('ميراث');
      await linkKeyword(included, kw1);
      await linkKeyword(excluded, kw2);

      final result = await repo.loadExportKeywords([included]);

      expect(result.keywords.map((k) => k.keywordText).toList(), ['عقود']);
      expect(result.documentKeywords, hasLength(1));
      expect(result.documentKeywords.single.documentCode, 'DOC-0000010');
      expect(result.documentKeywords.single.keywordText, 'عقود');
    });

    test('documentKeywords use documentCode not the integer id', () async {
      final docId = await addBaseDocument(
        documentCode: 'DOC-0000012',
        typeKey: 'book',
      );
      final kw = await addKeyword('نفقة');
      await linkKeyword(docId, kw);

      final result = await repo.loadExportKeywords([docId]);
      expect(result.documentKeywords.single.documentCode, 'DOC-0000012');
      expect(
        result.documentKeywords.single.documentCode,
        isNot(docId.toString()),
      );
    });
  });
}
