import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/database/seeding/reference_seeder.dart';

void main() {
  group('ReferenceSeeder', () {
    late AppDatabase db;
    late ReferenceSeeder seeder;

    setUp(() {
      db = AppDatabase.inMemory();
      seeder = ReferenceSeeder(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('seeds expected keys and bilingual names', () async {
      await seeder.seedAll();

      // Counts per finalized reference set.
      expect((await db.select(db.documentTypes).get()).length, 7);
      expect((await db.select(db.mainCategories).get()).length, 4);
      expect((await db.select(db.workflowStatuses).get()).length, 7);
      expect((await db.select(db.fileRoles).get()).length, 4);
      expect((await db.select(db.fileHealthStatuses).get()).length, 5);
      expect((await db.select(db.trustLevels).get()).length, 3);
      expect((await db.select(db.usageRights).get()).length, 5);
      expect((await db.select(db.metadataQualities).get()).length, 4);

      // Spot-check bilingual names across table shapes.
      final book = (await db.select(db.documentTypes).get()).firstWhere(
        (r) => r.key == 'book',
      );
      expect(book.nameAr, 'كتاب');
      expect(book.nameEn, 'Book');
      expect(book.isActive, isTrue);
      expect(book.sortOrder, 1);

      final publicLaw = (await db.select(db.mainCategories).get()).firstWhere(
        (r) => r.key == 'public_law',
      );
      expect(publicLaw.nameAr, 'القانون العام');
      expect(publicLaw.nameEn, 'Public Law');

      final copied = (await db.select(db.workflowStatuses).get()).firstWhere(
        (r) => r.key == 'copied_to_library',
      );
      // Copy-only policy: status must never use move ("نقل") wording.
      expect(copied.nameAr, 'نُسخ إلى المكتبة');
      expect(copied.nameAr, isNot(contains('نقل')));

      final unverified = (await db.select(db.trustLevels).get()).firstWhere(
        (r) => r.key == 'unverified',
      );
      expect(unverified.nameEn, 'Unverified');
    });

    test('running seeds twice creates no duplicates', () async {
      await seeder.seedAll();
      await seeder.seedAll();

      expect((await db.select(db.documentTypes).get()).length, 7);
      expect((await db.select(db.mainCategories).get()).length, 4);
      expect((await db.select(db.workflowStatuses).get()).length, 7);
      expect((await db.select(db.fileRoles).get()).length, 4);
      expect((await db.select(db.fileHealthStatuses).get()).length, 5);
      expect((await db.select(db.trustLevels).get()).length, 3);
      expect((await db.select(db.usageRights).get()).length, 5);
      expect((await db.select(db.metadataQualities).get()).length, 4);
    });

    test('existing matching keys are updated safely if names change', () async {
      // Pre-existing rows with stale display names (key-PK and id+key shapes).
      await db
          .into(db.documentTypes)
          .insert(
            DocumentTypesCompanion.insert(
              key: 'book',
              nameAr: 'اسم قديم',
              nameEn: 'Old Name',
              sortOrder: 99,
              isActive: false,
            ),
          );
      await db
          .into(db.trustLevels)
          .insert(
            TrustLevelsCompanion.insert(
              key: 'trusted',
              nameAr: 'قديم',
              nameEn: 'Old',
              sortOrder: 99,
              isActive: false,
            ),
          );

      await seeder.seedAll();

      // Still single rows, now carrying the canonical values.
      final books = (await db.select(db.documentTypes).get())
          .where((r) => r.key == 'book')
          .toList();
      expect(books.length, 1);
      expect(books.single.nameAr, 'كتاب');
      expect(books.single.nameEn, 'Book');
      expect(books.single.isActive, isTrue);
      expect(books.single.sortOrder, 1);

      final trusted = (await db.select(db.trustLevels).get()).firstWhere(
        (r) => r.key == 'trusted',
      );
      expect(trusted.nameAr, 'موثوق');
      expect(trusted.isActive, isTrue);
    });

    test(
      'seeding is transactional (rolls back on surrounding failure)',
      () async {
        // seedAll participates in a transaction: when the surrounding
        // transaction fails, none of the seeded rows are committed.
        await expectLater(
          db.transaction(() async {
            await seeder.seedAll();
            throw StateError('forced failure after seeding');
          }),
          throwsA(isA<StateError>()),
        );

        expect((await db.select(db.documentTypes).get()), isEmpty);
        expect((await db.select(db.workflowStatuses).get()), isEmpty);
        expect((await db.select(db.metadataQualities).get()), isEmpty);
      },
    );
  });
}
