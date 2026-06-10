import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/validation/category_name.dart';
import 'package:sqlite3/common.dart';

void main() {
  // All reference tables defined by this slice.
  const List<String> expectedTables = [
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
  ];

  // Schema tests share a single in-memory database. The setUp/tearDown live
  // inside this group so they do not leave an instance open during the
  // standalone open/close test below (which would trigger Drift's
  // multiple-database warning).
  group('reference schema', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase.inMemory();
    });

    tearDown(() async {
      await db.close();
    });

    test('all reference tables exist', () async {
      final List<QueryRow> rows = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'table';")
          .get();
      final Set<String> names = rows
          .map((QueryRow r) => r.read<String>('name'))
          .toSet();

      for (final String table in expectedTables) {
        expect(names, contains(table), reason: 'missing table $table');
      }
      // The temporary bootstrap table was removed.
      expect(names, isNot(contains('bootstrap_info')));
    });

    test('foreign keys remain enabled', () async {
      final QueryRow row = await db
          .customSelect('PRAGMA foreign_keys;')
          .getSingle();
      expect(row.read<int>('foreign_keys'), 1);
    });

    test('unique key rejects duplicates (document_types)', () async {
      await db
          .into(db.documentTypes)
          .insert(
            DocumentTypesCompanion.insert(
              key: 'book',
              nameAr: 'كتاب',
              nameEn: 'Book',
              sortOrder: 1,
              isActive: true,
            ),
          );

      expect(
        () => db
            .into(db.documentTypes)
            .insert(
              DocumentTypesCompanion.insert(
                key: 'book',
                nameAr: 'كتاب مكرر',
                nameEn: 'Duplicate Book',
                sortOrder: 2,
                isActive: true,
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('primary key rejects duplicate reference keys (languages)', () async {
      await db
          .into(db.languages)
          .insert(
            LanguagesCompanion.insert(
              key: 'ar',
              nameAr: 'العربية',
              nameEn: 'Arabic',
              sortOrder: 1,
              isActive: true,
            ),
          );

      expect(
        () => db
            .into(db.languages)
            .insert(
              LanguagesCompanion.insert(
                key: 'ar',
                nameAr: 'العربية',
                nameEn: 'Arabic',
                sortOrder: 2,
                isActive: true,
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('required bilingual names cannot be null', () async {
      // Raw insert bypassing the typed companion to hit the NOT NULL constraint.
      expect(
        () => db.customStatement(
          "INSERT INTO languages (key, name_ar, name_en, sort_order, is_active) "
          "VALUES ('en', NULL, 'English', 1, 1);",
        ),
        throwsA(isA<SqliteException>()),
      );

      expect(
        () => db.customStatement(
          "INSERT INTO languages (key, name_ar, name_en, sort_order, is_active) "
          "VALUES ('fr', 'الفرنسية', NULL, 1, 1);",
        ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('subcategory foreign key is enforced', () async {
      // Referencing a non-existent main category must fail.
      expect(
        () => db
            .into(db.subCategories)
            .insert(
              SubCategoriesCompanion.insert(
                mainCategoryId: 9999,
                key: 'criminal_law',
                nameAr: 'القانون الجنائي',
                nameEn: 'Criminal Law',
                normalizedNameAr: normalizedCategoryNameAr('القانون الجنائي'),
                normalizedNameEn: normalizedCategoryNameEn('Criminal Law'),
                sortOrder: 1,
                isActive: true,
              ),
            ),
        throwsA(isA<SqliteException>()),
      );

      // With a valid parent it succeeds.
      final int mainId = await db
          .into(db.mainCategories)
          .insert(
            MainCategoriesCompanion.insert(
              key: 'public_law',
              nameAr: 'القانون العام',
              nameEn: 'Public Law',
              normalizedNameAr: normalizedCategoryNameAr('القانون العام'),
              normalizedNameEn: normalizedCategoryNameEn('Public Law'),
              sortOrder: 1,
              isActive: true,
            ),
          );

      final int subId = await db
          .into(db.subCategories)
          .insert(
            SubCategoriesCompanion.insert(
              mainCategoryId: mainId,
              key: 'criminal_law',
              nameAr: 'القانون الجنائي',
              nameEn: 'Criminal Law',
              normalizedNameAr: normalizedCategoryNameAr('القانون الجنائي'),
              normalizedNameEn: normalizedCategoryNameEn('Criminal Law'),
              sortOrder: 1,
              isActive: true,
            ),
          );
      expect(subId, greaterThan(0));
    });
  });

  // No shared database is open here: each instance is created, used, then
  // closed before the next one opens, so only one exists at a time.
  test('test database can be created and closed safely', () async {
    final AppDatabase first = AppDatabase.inMemory();
    await first.customSelect('SELECT 1;').get();
    await first.close();

    final AppDatabase second = AppDatabase.inMemory();
    await second.customSelect('SELECT 1;').get();
    await second.close();
  });
}
