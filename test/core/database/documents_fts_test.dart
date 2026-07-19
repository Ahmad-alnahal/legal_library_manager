import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/database/seeding/reference_seeder.dart';

void main() {
  group('AppDatabase FTS helpers', () {
    late AppDatabase db;
    const String now = '2026-07-19T10:00:00Z';

    setUp(() async {
      db = AppDatabase.inMemory();
      await ReferenceSeeder(db).seedAll();
    });

    tearDown(() => db.close());

    Future<int> doc({String? title}) => db
        .into(db.documents)
        .insert(
          DocumentsCompanion.insert(
            title: Value(title),
            createdAt: now,
            updatedAt: now,
          ),
        );

    Future<List<int>> matchRowIds(String query) async {
      final rows = await db
          .customSelect(
            'SELECT rowid FROM documents_fts WHERE documents_fts MATCH ?',
            variables: [Variable<String>(query)],
          )
          .get();
      return rows.map((r) => r.read<int>('rowid')).toList();
    }

    group('updateDocumentFts', () {
      test('inserts an entry findable by title', () async {
        final id = await doc(title: 'قانون العمل');
        await db.updateDocumentFts(id);

        expect(await matchRowIds('العمل*'), contains(id));
      });

      test(
        'replaces the entry when the title changes, not duplicates it',
        () async {
          final id = await doc(title: 'العنوان الأول');
          await db.updateDocumentFts(id);

          await (db.update(db.documents)..where((d) => d.id.equals(id))).write(
            const DocumentsCompanion(title: Value('العنوان الثاني')),
          );
          await db.updateDocumentFts(id);

          expect(await matchRowIds('الأول*'), isEmpty);
          expect(await matchRowIds('الثاني*'), [id]);

          final count =
              (await db
                      .customSelect(
                        'SELECT COUNT(*) AS c FROM documents_fts WHERE rowid = ?',
                        variables: [Variable<int>(id)],
                      )
                      .getSingle())
                  .read<int>('c');
          expect(count, 1);
        },
      );
    });

    group('rebuildFtsIndex', () {
      test('indexes every existing document', () async {
        final a = await doc(title: 'وثيقة ألف');
        final b = await doc(title: 'وثيقة باء');
        final c = await doc(title: 'وثيقة جيم');

        await db.rebuildFtsIndex();

        expect(await matchRowIds('ألف*'), [a]);
        expect(await matchRowIds('باء*'), [b]);
        expect(await matchRowIds('جيم*'), [c]);
      });

      test('is idempotent: calling twice does not duplicate rows', () async {
        final id = await doc(title: 'وثيقة فريدة');

        await db.rebuildFtsIndex();
        await db.rebuildFtsIndex();

        final count =
            (await db
                    .customSelect(
                      'SELECT COUNT(*) AS c FROM documents_fts WHERE rowid = ?',
                      variables: [Variable<int>(id)],
                    )
                    .getSingle())
                .read<int>('c');
        expect(count, 1);
      });
    });
  });
}
