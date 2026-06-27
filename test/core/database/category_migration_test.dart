import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/validation/category_name.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

/// Creates the pre-M6.4 (schema version 1) category tables and seeds them on
/// [raw]: a couple of main categories and a subcategory, with no normalized
/// columns or indexes. When [withCollision] is true, a second main category
/// whose name only differs by whitespace is added so the stronger v2
/// normalization would map it onto the first.
void writeV1Schema(Database raw, {required bool withCollision}) {
  raw.execute('''
    CREATE TABLE main_categories (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      key TEXT NOT NULL UNIQUE,
      name_ar TEXT NOT NULL,
      name_en TEXT NOT NULL,
      sort_order INTEGER NOT NULL,
      is_active INTEGER NOT NULL
    );
  ''');
  raw.execute('''
    CREATE TABLE sub_categories (
      id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
      main_category_id INTEGER NOT NULL REFERENCES main_categories (id),
      key TEXT NOT NULL UNIQUE,
      name_ar TEXT NOT NULL,
      name_en TEXT NOT NULL,
      sort_order INTEGER NOT NULL,
      is_active INTEGER NOT NULL
    );
  ''');

  raw.execute(
    'INSERT INTO main_categories (key, name_ar, name_en, sort_order, is_active) '
    "VALUES ('public_law', 'القانون العام', 'Public Law', 1, 1)",
  );
  raw.execute(
    'INSERT INTO main_categories (key, name_ar, name_en, sort_order, is_active) '
    "VALUES ('private_law', 'القانون الخاص', 'Private Law', 2, 1)",
  );
  raw.execute(
    'INSERT INTO sub_categories '
    '(main_category_id, key, name_ar, name_en, sort_order, is_active) '
    "VALUES (1, 'constitutional_law', 'القانون الدستوري', "
    "'Constitutional Law', 1, 1)",
  );

  if (withCollision) {
    raw.execute(
      'INSERT INTO main_categories '
      '(key, name_ar, name_en, sort_order, is_active) '
      "VALUES ('public_law_dup', '  القانون   العام ', 'Public  Law', 3, 1)",
    );
  }

  raw.execute('PRAGMA user_version = 1;');
}

void main() {
  const List<String> categoryIndexes = [
    'ux_main_categories_normalized_name_ar',
    'ux_main_categories_normalized_name_en',
    'ux_sub_categories_main_normalized_name_ar',
    'ux_sub_categories_main_normalized_name_en',
  ];

  test('a fresh database is created directly at version 4', () async {
    final AppDatabase db = AppDatabase.inMemory();
    addTearDown(db.close);

    final int version =
        (await db.customSelect('PRAGMA user_version;').getSingle()).read<int>(
          'user_version',
        );
    expect(version, 4);

    final Set<String> indexes =
        (await db
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type = 'index';",
                )
                .get())
            .map((r) => r.read<String>('name'))
            .toSet();
    expect(indexes, containsAll(categoryIndexes));
  });

  test('migrates a valid v1 database and backfills normalized names', () async {
    final Database raw = sqlite3.openInMemory();
    writeV1Schema(raw, withCollision: false);
    final AppDatabase db = AppDatabase.forExecutor(NativeDatabase.opened(raw));
    addTearDown(db.close);

    // Trigger the open + migration.
    await db.customSelect('SELECT 1;').get();

    // Schema version is now 4 (v1→v2 category migration, v2→v3 security
    // tables, v3→v4 paired_count) and the category indexes exist.
    expect(
      (await db.customSelect('PRAGMA user_version;').getSingle()).read<int>(
        'user_version',
      ),
      4,
    );
    final Set<String> indexes =
        (await db
                .customSelect(
                  "SELECT name FROM sqlite_master WHERE type = 'index';",
                )
                .get())
            .map((r) => r.read<String>('name'))
            .toSet();
    expect(indexes, containsAll(categoryIndexes));

    // Every row's normalized values match the shared normalization.
    final List<QueryRow> mains = await db
        .customSelect(
          'SELECT key, name_ar, name_en, normalized_name_ar, '
          'normalized_name_en, id FROM main_categories ORDER BY id',
        )
        .get();
    for (final QueryRow r in mains) {
      expect(
        r.read<String>('normalized_name_ar'),
        normalizedCategoryNameAr(r.read<String>('name_ar')),
      );
      expect(
        r.read<String>('normalized_name_en'),
        normalizedCategoryNameEn(r.read<String>('name_en')),
      );
    }

    // IDs and keys are preserved (no merge/rename/delete).
    expect(mains.map((r) => r.read<String>('key')).toList(), [
      'public_law',
      'private_law',
    ]);
    expect(mains.first.read<int>('id'), 1);

    // Subcategory references remain valid: the sub still points at its main.
    final QueryRow sub = await db
        .customSelect(
          'SELECT main_category_id, normalized_name_ar FROM sub_categories '
          "WHERE key = 'constitutional_law'",
        )
        .getSingle();
    expect(sub.read<int>('main_category_id'), 1);
    expect(
      sub.read<String>('normalized_name_ar'),
      normalizedCategoryNameAr('القانون الدستوري'),
    );
  });

  test('aborts and rolls back when a collision is detected', () async {
    // A file-backed database so the rolled-back state can be inspected with a
    // fresh connection after the failed migration.
    final Directory dir = await Directory.systemTemp.createTemp('marjiy_mig');
    final String path = p.join(dir.path, 'v1.sqlite');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    final Database seed = sqlite3.open(path);
    writeV1Schema(seed, withCollision: true);
    seed.close();

    final AppDatabase db = AppDatabase.forExecutor(NativeDatabase(File(path)));

    // Opening triggers the migration, which must abort on the collision.
    await expectLater(
      db.customSelect('SELECT 1;').get(),
      throwsA(
        predicate(
          (Object? e) =>
              e.toString().contains('CategoryNormalizationCollision'),
        ),
      ),
    );
    try {
      await db.close();
    } catch (_) {
      // The failed open may already have torn down the connection.
    }

    // The v1 database is left completely unchanged: no normalized columns, no
    // normalized indexes, version still 1, and no rows touched.
    final Database check = sqlite3.open(path);
    final List<String> mainColumns = check
        .select('PRAGMA table_info(main_categories);')
        .map((r) => r['name'] as String)
        .toList();
    final Set<String> indexes = check
        .select("SELECT name FROM sqlite_master WHERE type = 'index';")
        .map((r) => r['name'] as String)
        .toSet();
    final int version =
        check.select('PRAGMA user_version;').first['user_version'] as int;
    final int count =
        check.select('SELECT COUNT(*) AS c FROM main_categories;').first['c']
            as int;
    check.close();

    expect(mainColumns, isNot(contains('normalized_name_ar')));
    expect(indexes.intersection(categoryIndexes.toSet()), isEmpty);
    expect(version, 1);
    expect(count, 3);
  });
}
