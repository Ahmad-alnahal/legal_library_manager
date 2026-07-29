import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/database/seeding/reference_seeder.dart';
import 'package:legal_library_manager/features/reference/data/repositories/drift_reference_repository.dart';
import 'package:legal_library_manager/features/reference/domain/repositories/reference_repository.dart';

void main() {
  group('DriftReferenceRepository', () {
    late AppDatabase db;
    late ReferenceRepository repo;

    setUp(() async {
      db = AppDatabase.inMemory();
      await ReferenceSeeder(db).seedAll();
      repo = DriftReferenceRepository(db);
    });

    tearDown(() async {
      await db.close();
    });

    bool isSortedBySortOrder(List<int> orders) {
      for (int i = 1; i < orders.length; i++) {
        if (orders[i] < orders[i - 1]) return false;
      }
      return true;
    }

    test('returns all reference sets with stable counts', () async {
      expect((await repo.getDocumentTypes()).length, 7);
      expect((await repo.getMainCategories()).length, 4);
      expect((await repo.getSubCategories()).length, 17);
      expect((await repo.getLanguages()).length, 3);
      expect((await repo.getCountries()).length, 249);
      expect((await repo.getTrustLevels()).length, 3);
      expect((await repo.getUsageRights()).length, 5);
      expect((await repo.getMetadataQualities()).length, 4);
      expect((await repo.getWorkflowStatuses()).length, 7);
      expect((await repo.getFileRoles()).length, 4);
      expect((await repo.getFileHealthStatuses()).length, 5);
    });

    test(
      'countries are returned in Arabic alphabetical order with Palestine '
      'first',
      () async {
        final countries = await repo.getCountries();
        expect(countries.first.key, 'ps');
        final rest = countries.skip(1).map((c) => c.nameAr).toList();
        final sorted = [...rest]..sort();
        expect(rest, sorted);
      },
    );

    test('document types are ordered by sort order', () async {
      final types = await repo.getDocumentTypes();
      expect(
        isSortedBySortOrder(types.map((t) => t.sortOrder).toList()),
        isTrue,
      );
    });

    test('returns only active rows by default', () async {
      // Deactivate one country and one subcategory.
      await (db.update(db.countries)..where((c) => c.key.equals('jo'))).write(
        const CountriesCompanion(isActive: Value(false)),
      );
      await (db.update(db.subCategories)
            ..where((s) => s.key.equals('civil_law')))
          .write(const SubCategoriesCompanion(isActive: Value(false)));

      final countries = await repo.getCountries();
      expect(countries.any((c) => c.key == 'jo'), isFalse);
      expect(countries.length, 248);

      final subs = await repo.getSubCategories();
      expect(subs.any((s) => s.key == 'civil_law'), isFalse);
      expect(subs.length, 16);
    });

    test('country lookup by key returns the matching active row', () async {
      final ps = await repo.getCountryByKey('ps');
      expect(ps, isNotNull);
      expect(ps!.nameEn, 'State of Palestine');
      expect(ps.nameAr, 'دولة فلسطين');

      expect(await repo.getCountryByKey('zz'), isNull);
    });

    test('country lookup excludes inactive rows', () async {
      await (db.update(db.countries)..where((c) => c.key.equals('jo'))).write(
        const CountriesCompanion(isActive: Value(false)),
      );
      expect(await repo.getCountryByKey('jo'), isNull);
    });

    test('subcategory filtering by main-category id works', () async {
      final mains = await repo.getMainCategories();
      final publicLaw = mains.firstWhere((m) => m.key == 'public_law');
      final subs = await repo.getSubCategories(mainCategoryId: publicLaw.id);
      expect(subs.length, 4);
      expect(subs.every((s) => s.mainCategoryId == publicLaw.id), isTrue);
      expect(subs.map((s) => s.key), [
        'constitutional_law',
        'administrative_law',
        'criminal_law',
        'human_rights',
      ]);
    });

    test('subcategory filtering by main-category key works', () async {
      final subs = await repo.getSubCategories(
        mainCategoryKey: 'international_law',
      );
      expect(subs.length, 6);
      expect(subs.first.key, 'public_international_law');
    });

    test('subcategory filtering by unknown key returns empty', () async {
      final subs = await repo.getSubCategories(
        mainCategoryKey: 'does_not_exist',
      );
      expect(subs, isEmpty);
    });

    test('supplying both subcategory filters throws ArgumentError', () async {
      final mains = await repo.getMainCategories();
      final publicLaw = mains.firstWhere((m) => m.key == 'public_law');
      await expectLater(
        repo.getSubCategories(
          mainCategoryId: publicLaw.id,
          mainCategoryKey: 'public_law',
        ),
        throwsArgumentError,
      );
    });
  });
}
