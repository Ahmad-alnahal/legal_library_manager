import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/database/seeding/country_seed_data.dart';
import 'package:legal_library_manager/core/database/seeding/reference_seeder.dart';

void main() {
  group('ReferenceSeeder languages', () {
    late AppDatabase db;
    late ReferenceSeeder seeder;

    setUp(() {
      db = AppDatabase.inMemory();
      seeder = ReferenceSeeder(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('Arabic, English, and Other are seeded as languages', () async {
      await seeder.seedAll();
      final rows = await db.select(db.languages).get();
      expect(rows.length, 3);
      final byKey = {for (final r in rows) r.key: r};
      expect(byKey['ar']!.nameAr, 'العربية');
      expect(byKey['ar']!.nameEn, 'Arabic');
      expect(byKey['en']!.nameAr, 'الإنجليزية');
      expect(byKey['en']!.nameEn, 'English');
      expect(byKey['other']!.nameAr, 'أخرى');
      expect(byKey['other']!.nameEn, 'Other');
      for (final r in rows) {
        expect(r.isActive, isTrue);
      }
    });

    test('re-running does not duplicate the languages', () async {
      await seeder.seedAll();
      await seeder.seedAll();
      expect((await db.select(db.languages).get()).length, 3);
    });

    test('stale language row is restored to canonical state', () async {
      await seeder.seedAll();
      await (db.update(db.languages)..where((l) => l.key.equals('ar'))).write(
        const LanguagesCompanion(
          nameAr: Value('قديم'),
          nameEn: Value('Old'),
          isActive: Value(false),
        ),
      );
      await seeder.seedAll();
      final ar = (await db.select(
        db.languages,
      ).get()).firstWhere((l) => l.key == 'ar');
      expect(ar.nameEn, 'Arabic');
      expect(ar.isActive, isTrue);
    });
  });

  group('ReferenceSeeder countries', () {
    late AppDatabase db;
    late ReferenceSeeder seeder;

    setUp(() {
      db = AppDatabase.inMemory();
      seeder = ReferenceSeeder(db);
    });

    tearDown(() async {
      await db.close();
    });

    test('seeds exactly 249 ISO countries', () async {
      await seeder.seedAll();
      expect((await db.select(db.countries).get()).length, 249);
    });

    test('the dataset module itself holds 249 unique entries', () {
      expect(kCountrySeedData.length, 249);
      expect(kCountrySeedData.map((c) => c.key).toSet().length, 249);
      expect(orderedCountrySeedData().length, 249);
    });

    test('every key is unique, lowercase, and exactly two letters', () async {
      await seeder.seedAll();
      final rows = await db.select(db.countries).get();
      final keys = rows.map((r) => r.key).toList();
      expect(keys.toSet().length, keys.length, reason: 'keys must be unique');
      final twoLowerLetters = RegExp(r'^[a-z]{2}$');
      for (final k in keys) {
        expect(twoLowerLetters.hasMatch(k), isTrue, reason: 'bad key: $k');
      }
    });

    test('ps has approved names and the first sort order', () async {
      await seeder.seedAll();
      final ps = (await db.select(db.countries).get()).firstWhere(
        (c) => c.key == 'ps',
      );
      expect(ps.nameAr, 'دولة فلسطين');
      expect(ps.nameEn, 'State of Palestine');
      expect(ps.isActive, isTrue);
      expect(ps.sortOrder, 1);

      // No other country shares the first sort order.
      final firsts = (await db.select(db.countries).get())
          .where((c) => c.sortOrder == 1)
          .toList();
      expect(firsts.length, 1);
      expect(firsts.single.key, 'ps');
    });

    test('remaining entries are ordered by English display name', () async {
      await seeder.seedAll();
      final rows = (await db.select(db.countries).get())
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      // Drop the pinned Palestine entry, the rest must be English-name sorted.
      final rest = rows.skip(1).map((r) => r.nameEn).toList();
      final sorted = [...rest]..sort();
      expect(rest, sorted);
    });

    test(
      'representative entries across regions and territories exist',
      () async {
        await seeder.seedAll();
        final byKey = {
          for (final c in await db.select(db.countries).get()) c.key: c,
        };
        // Arab states, major powers, small states, and dependent territories.
        for (final k in [
          'jo', 'sa', 'eg', 'us', 'jp', 'gb', 'fr', 'cn', 'br', 'za', 'au',
          'aq', // Antarctica
          'gs', // South Georgia and the South Sandwich Islands
          'um', // US Minor Outlying Islands
          'va', // Holy See
          'tw', // Taiwan, Province of China
        ]) {
          expect(byKey.containsKey(k), isTrue, reason: 'missing $k');
          expect(byKey[k]!.nameAr.isNotEmpty, isTrue);
          expect(byKey[k]!.nameEn.isNotEmpty, isTrue);
        }
      },
    );

    test('country seeding is idempotent', () async {
      await seeder.seedAll();
      await seeder.seedAll();
      expect((await db.select(db.countries).get()).length, 249);
    });

    test('stale country rows are restored without duplicates', () async {
      await seeder.seedAll();
      await (db.update(db.countries)..where((c) => c.key.equals('jo'))).write(
        const CountriesCompanion(
          nameAr: Value('قديم'),
          nameEn: Value('Old Jordan'),
          sortOrder: Value(999),
          isActive: Value(false),
        ),
      );
      await seeder.seedAll();
      final jo = (await db.select(db.countries).get()).firstWhere(
        (c) => c.key == 'jo',
      );
      expect(jo.nameAr, 'الأردن');
      expect(jo.nameEn, 'Jordan');
      expect(jo.isActive, isTrue);
      expect((await db.select(db.countries).get()).length, 249);
    });
  });
}
