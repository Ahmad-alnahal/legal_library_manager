import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/database/seeding/reference_seeder.dart';

void main() {
  group('ReferenceSeeder subcategories', () {
    late AppDatabase db;
    late ReferenceSeeder seeder;

    setUp(() {
      db = AppDatabase.inMemory();
      seeder = ReferenceSeeder(db);
    });

    tearDown(() async {
      await db.close();
    });

    // Canonical parent -> ordered subcategory keys.
    const Map<String, List<String>> expected = {
      'public_law': [
        'constitutional_law',
        'administrative_law',
        'criminal_law',
        'human_rights',
      ],
      'private_law': [
        'civil_law',
        'commercial_law',
        'corporate_law',
        'insurance_law',
      ],
      'international_law': [
        'public_international_law',
        'international_humanitarian_law',
        'private_international_law',
        'international_criminal_law',
        'international_human_rights_law',
        'diplomatic_law',
      ],
      'islamic_jurisprudence': [
        'principles_of_islamic_jurisprudence',
        'islamic_criminal_jurisprudence',
        'islamic_civil_and_transactions_jurisprudence',
      ],
    };

    test('seeds exactly 17 active subcategories', () async {
      await seeder.seedAll();
      final rows = await db.select(db.subCategories).get();
      expect(rows.length, 17);
      expect(rows.every((r) => r.isActive), isTrue);
    });

    test('every subcategory belongs to its correct main category', () async {
      await seeder.seedAll();
      final cats = await db.select(db.mainCategories).get();
      final Map<int, String> keyById = {for (final c in cats) c.id: c.key};
      final subs = await db.select(db.subCategories).get();

      for (final entry in expected.entries) {
        for (final subKey in entry.value) {
          final sub = subs.firstWhere((s) => s.key == subKey);
          expect(
            keyById[sub.mainCategoryId],
            entry.key,
            reason: '$subKey should belong to ${entry.key}',
          );
        }
      }
    });

    test('per-parent sort order restarts at 1 and matches spec', () async {
      await seeder.seedAll();
      final cats = await db.select(db.mainCategories).get();
      final Map<String, int> idByKey = {for (final c in cats) c.key: c.id};
      final subs = await db.select(db.subCategories).get();

      for (final entry in expected.entries) {
        final parentId = idByKey[entry.key]!;
        final ordered = subs.where((s) => s.mainCategoryId == parentId).toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
        expect(ordered.map((s) => s.key).toList(), entry.value);
        expect(ordered.map((s) => s.sortOrder).toList(), [
          for (int i = 1; i <= entry.value.length; i++) i,
        ]);
      }
    });

    test('bilingual names are populated for a representative entry', () async {
      await seeder.seedAll();
      final sub = (await db.select(db.subCategories).get()).firstWhere(
        (s) => s.key == 'constitutional_law',
      );
      expect(sub.nameAr, 'القانون الدستوري');
      expect(sub.nameEn, 'Constitutional Law');
    });

    test('re-running does not duplicate subcategories', () async {
      await seeder.seedAll();
      await seeder.seedAll();
      expect((await db.select(db.subCategories).get()).length, 17);
    });

    test('stale subcategory rows are restored to canonical state', () async {
      await seeder.seedAll();
      final cats = await db.select(db.mainCategories).get();
      final wrongParent = cats.firstWhere(
        (c) => c.key == 'islamic_jurisprudence',
      );

      // Corrupt a row: wrong parent, names, order, inactive.
      await (db.update(
        db.subCategories,
      )..where((s) => s.key.equals('constitutional_law'))).write(
        SubCategoriesCompanion(
          mainCategoryId: Value(wrongParent.id),
          nameAr: const Value('stale ar'),
          nameEn: const Value('Stale'),
          sortOrder: const Value(99),
          isActive: const Value(false),
        ),
      );

      await seeder.seedAll();

      final cats2 = await db.select(db.mainCategories).get();
      final publicLawId = cats2.firstWhere((c) => c.key == 'public_law').id;
      final sub = (await db.select(db.subCategories).get()).firstWhere(
        (s) => s.key == 'constitutional_law',
      );
      expect(sub.mainCategoryId, publicLawId);
      expect(sub.nameAr, 'القانون الدستوري');
      expect(sub.nameEn, 'Constitutional Law');
      expect(sub.sortOrder, 1);
      expect(sub.isActive, isTrue);
      expect((await db.select(db.subCategories).get()).length, 17);
    });
  });
}
