// `isNull` is exported by both drift and matcher; keep matcher's for tests.
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/database/seeding/reference_seeder.dart';
import 'package:legal_library_manager/core/validation/category_name.dart';
import 'package:sqlite3/common.dart';

void main() {
  group('classifications / keywords schema', () {
    late AppDatabase db;
    const String nowIso = '2026-06-06T10:00:00Z';

    setUp(() async {
      db = AppDatabase.inMemory();
      // Seed reference data so main_categories / document defaults resolve.
      await ReferenceSeeder(db).seedAll();
    });

    tearDown(() async {
      await db.close();
    });

    Future<int> insertDocument() => db
        .into(db.documents)
        .insert(
          DocumentsCompanion.insert(createdAt: nowIso, updatedAt: nowIso),
        );

    Future<int> mainCategoryId(String key) async => (await (db.select(
      db.mainCategories,
    )..where((c) => c.key.equals(key))).getSingle()).id;

    Future<int> insertSubCategory(int parentId, String key) => db
        .into(db.subCategories)
        .insert(
          SubCategoriesCompanion.insert(
            mainCategoryId: parentId,
            key: key,
            nameAr: 'فرع',
            nameEn: 'Sub',
            normalizedNameAr: normalizedCategoryNameAr('فرع'),
            normalizedNameEn: normalizedCategoryNameEn('Sub'),
            sortOrder: 1,
            isActive: true,
          ),
        );

    Future<int> insertClassification({
      required int documentId,
      required int mainId,
      Value<int?> subId = const Value.absent(),
      String role = 'additional',
    }) => db
        .into(db.documentClassifications)
        .insert(
          DocumentClassificationsCompanion.insert(
            documentId: documentId,
            mainCategoryId: mainId,
            classificationRoleKey: role,
            createdAt: nowIso,
            subCategoryId: subId,
          ),
        );

    Future<int> insertKeyword({
      required String normalized,
      Value<String?> languageKey = const Value.absent(),
    }) => db
        .into(db.keywords)
        .insert(
          KeywordsCompanion.insert(
            normalizedValue: normalized,
            displayValue: normalized,
            createdAt: nowIso,
            languageKey: languageKey,
          ),
        );

    Future<void> linkKeyword(int documentId, int keywordId) => db
        .into(db.documentKeywords)
        .insert(
          DocumentKeywordsCompanion.insert(
            documentId: documentId,
            keywordId: keywordId,
            createdAt: nowIso,
          ),
        );

    test('required tables and indexes exist', () async {
      final Set<String> tables =
          (await db
                  .customSelect(
                    "SELECT name FROM sqlite_master WHERE type = 'table';",
                  )
                  .get())
              .map((QueryRow r) => r.read<String>('name'))
              .toSet();
      expect(
        tables,
        containsAll(<String>[
          'document_classifications',
          'keywords',
          'document_keywords',
        ]),
      );

      final Set<String> indexes =
          (await db
                  .customSelect(
                    "SELECT name FROM sqlite_master WHERE type = 'index';",
                  )
                  .get())
              .map((QueryRow r) => r.read<String>('name'))
              .toSet();
      const List<String> required = [
        'ix_document_classifications_document_id',
        'ix_document_classifications_main_sub',
        'ux_document_classifications_primary',
        'ux_document_classifications_combo_sub',
        'ux_document_classifications_combo_nosub',
        'ux_keywords_normalized_value',
        'ix_document_keywords_keyword_id',
      ];
      for (final String name in required) {
        expect(indexes, contains(name), reason: 'missing index $name');
      }
    });

    test('only valid classification roles are accepted', () async {
      final int docId = await insertDocument();
      final int mainId = await mainCategoryId('public_law');

      // Valid roles.
      await insertClassification(
        documentId: docId,
        mainId: mainId,
        role: 'primary',
      );
      final int otherMain = await mainCategoryId('private_law');
      await insertClassification(
        documentId: docId,
        mainId: otherMain,
        role: 'additional',
      );

      // Invalid role rejected by CHECK.
      final int intlMain = await mainCategoryId('international_law');
      expect(
        () => insertClassification(
          documentId: docId,
          mainId: intlMain,
          role: 'bogus',
        ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('a document cannot have two primary classifications', () async {
      final int docId = await insertDocument();
      await insertClassification(
        documentId: docId,
        mainId: await mainCategoryId('public_law'),
        role: 'primary',
      );
      final int privateMain = await mainCategoryId('private_law');
      expect(
        () => insertClassification(
          documentId: docId,
          mainId: privateMain,
          role: 'primary',
        ),
        throwsA(isA<SqliteException>()),
      );
    });

    test(
      'duplicate combinations are rejected (with NULL subcategory)',
      () async {
        final int docId = await insertDocument();
        final int mainId = await mainCategoryId('public_law');

        // NULL-subcategory duplicate.
        await insertClassification(documentId: docId, mainId: mainId);
        expect(
          () => insertClassification(documentId: docId, mainId: mainId),
          throwsA(isA<SqliteException>()),
        );

        // Subcategory duplicate (uses a test-only key not in the seed set).
        final int subId = await insertSubCategory(mainId, 'test_dup_combo_sub');
        await insertClassification(
          documentId: docId,
          mainId: mainId,
          subId: Value(subId),
        );
        expect(
          () => insertClassification(
            documentId: docId,
            mainId: mainId,
            subId: Value(subId),
          ),
          throwsA(isA<SqliteException>()),
        );
      },
    );

    test(
      'classifications and keyword joins cascade on document delete',
      () async {
        final int docId = await insertDocument();
        await insertClassification(
          documentId: docId,
          mainId: await mainCategoryId('public_law'),
          role: 'primary',
        );
        final int kwId = await insertKeyword(normalized: 'aqd');
        await linkKeyword(docId, kwId);

        final int deleted = await (db.delete(
          db.documents,
        )..where((d) => d.id.equals(docId))).go();
        expect(deleted, 1);

        expect(await db.select(db.documentClassifications).get(), isEmpty);
        expect(await db.select(db.documentKeywords).get(), isEmpty);
        // The keyword row itself is not cascaded.
        expect((await db.select(db.keywords).get()).length, 1);
      },
    );

    test('category / language / keyword deletion is restricted', () async {
      final int docId = await insertDocument();
      final int mainId = await mainCategoryId('public_law');
      await insertClassification(
        documentId: docId,
        mainId: mainId,
        role: 'primary',
      );

      // Main category referenced by a classification cannot be deleted.
      expect(
        () => (db.delete(
          db.mainCategories,
        )..where((c) => c.id.equals(mainId))).go(),
        throwsA(isA<SqliteException>()),
      );

      // Language referenced by a keyword cannot be deleted. Arabic (`ar`) is
      // already seeded by ReferenceSeeder in setUp.
      final int kwId = await insertKeyword(
        normalized: 'haqq',
        languageKey: const Value('ar'),
      );
      expect(
        () => (db.delete(db.languages)..where((l) => l.key.equals('ar'))).go(),
        throwsA(isA<SqliteException>()),
      );

      // Keyword referenced by a document_keywords link cannot be deleted.
      await linkKeyword(docId, kwId);
      expect(
        () => (db.delete(db.keywords)..where((k) => k.id.equals(kwId))).go(),
        throwsA(isA<SqliteException>()),
      );
    });

    test('keyword normalization is unique and join PK is composite', () async {
      final int docId = await insertDocument();
      await insertKeyword(normalized: 'qanun');
      expect(
        () => insertKeyword(normalized: 'qanun'),
        throwsA(isA<SqliteException>()),
      );

      final int kwId = await insertKeyword(normalized: 'mahkama');
      await linkKeyword(docId, kwId);
      // Same (document_id, keyword_id) violates the composite primary key.
      expect(() => linkKeyword(docId, kwId), throwsA(isA<SqliteException>()));
    });
  });
}
