import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/database/seeding/reference_seeder.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

void main() {
  const String now = '2026-07-19T10:00:00Z';

  test(
    'a fresh database is created directly at version 9 with documents_fts',
    () async {
      final AppDatabase db = AppDatabase.inMemory();
      addTearDown(db.close);

      final int version =
          (await db.customSelect('PRAGMA user_version;').getSingle()).read<int>(
            'user_version',
          );
      expect(version, 9);

      final Set<String> tables =
          (await db
                  .customSelect(
                    "SELECT name FROM sqlite_master WHERE type IN ('table', 'view');",
                  )
                  .get())
              .map((r) => r.read<String>('name'))
              .toSet();
      expect(tables, contains('documents_fts'));
    },
  );

  test(
    'migrating a v7 database creates documents_fts and indexes existing documents',
    () async {
      // Build a real v7-shaped database on disk: start from a fresh AppDatabase
      // (created directly at the current version), then strip the v8-only
      // documents_fts table and roll the recorded version back to 7 so a fresh
      // AppDatabase instance re-triggers the v7->v8 upgrade path on open.
      final Directory dir = await Directory.systemTemp.createTemp(
        'marjiy_fts_mig',
      );
      final String path = p.join(dir.path, 'v7.sqlite');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      final AppDatabase seedDb = AppDatabase.forExecutor(
        NativeDatabase(File(path)),
      );
      await ReferenceSeeder(seedDb).seedAll();
      final int documentId = await seedDb
          .into(seedDb.documents)
          .insert(
            DocumentsCompanion.insert(
              title: const Value('قانون العمل الأردني'),
              summary: const Value('ملخص القانون'),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await seedDb.close();

      final Database raw = sqlite3.open(path);
      raw.execute('DROP TABLE documents_fts;');
      raw.execute('PRAGMA user_version = 7;');
      raw.close();

      final AppDatabase db = AppDatabase.forExecutor(
        NativeDatabase(File(path)),
      );

      // Trigger the open + migration.
      await db.customSelect('SELECT 1;').get();

      expect(
        (await db.customSelect('PRAGMA user_version;').getSingle()).read<int>(
          'user_version',
        ),
        9,
      );

      final Set<String> tables =
          (await db
                  .customSelect(
                    "SELECT name FROM sqlite_master WHERE type IN ('table', 'view');",
                  )
                  .get())
              .map((r) => r.read<String>('name'))
              .toSet();
      expect(tables, contains('documents_fts'));

      final List<QueryRow> found = await db
          .customSelect(
            "SELECT rowid FROM documents_fts WHERE documents_fts MATCH 'قانون*'",
          )
          .get();
      expect(found.map((r) => r.read<int>('rowid')), contains(documentId));

      // Explicit close (not addTearDown) so the file is released before this
      // test's temp-dir teardown runs.
      await db.close();
    },
  );
}
