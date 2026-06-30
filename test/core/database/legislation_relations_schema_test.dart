// `isNull` is exported by both drift and matcher; keep matcher's for tests.
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/database/seeding/reference_seeder.dart';
import 'package:sqlite3/common.dart';

void main() {
  group('legislation_relations table', () {
    late AppDatabase db;
    const String now = '2026-06-29T10:00:00Z';

    setUp(() async {
      db = AppDatabase.inMemory();
      await ReferenceSeeder(db).seedAll();
    });

    tearDown(() => db.close());

    Future<int> doc() => db
        .into(db.documents)
        .insert(DocumentsCompanion.insert(createdAt: now, updatedAt: now));

    Future<int> relation({
      required int source,
      required int target,
      String type = 'repeals',
      String scope = 'full',
    }) => db
        .into(db.legislationRelations)
        .insert(
          LegislationRelationsCompanion.insert(
            sourceDocumentId: source,
            targetDocumentId: target,
            relationTypeKey: type,
            relationScopeKey: Value(scope),
            createdAt: now,
            updatedAt: now,
          ),
        );

    test('table exists', () async {
      final tables =
          (await db
                  .customSelect(
                    "SELECT name FROM sqlite_master WHERE type='table' "
                    "AND name='legislation_relations';",
                  )
                  .get())
              .map((r) => r.read<String>('name'))
              .toSet();
      expect(tables, contains('legislation_relations'));
    });

    test('insert valid relation succeeds', () async {
      final src = await doc();
      final tgt = await doc();
      final id = await relation(source: src, target: tgt);
      expect(id, greaterThan(0));
    });

    test('all five relation_type_key values are accepted', () async {
      final src = await doc();
      for (final type in const [
        'repeals',
        'amends',
        'implements',
        'based_on',
        'supersedes',
      ]) {
        final tgt = await doc();
        await expectLater(
          relation(source: src, target: tgt, type: type),
          completes,
          reason: 'type=$type should be accepted',
        );
      }
    });

    test('invalid relation_type_key is rejected', () async {
      final src = await doc();
      final tgt = await doc();
      expect(
        () => relation(source: src, target: tgt, type: 'implementing'),
        throwsA(isA<SqliteException>()),
      );
    });

    test('all three scope values are accepted', () async {
      final src = await doc();
      for (final scope in const ['full', 'partial', 'unknown']) {
        final tgt = await doc();
        await expectLater(
          relation(source: src, target: tgt, scope: scope),
          completes,
          reason: 'scope=$scope should be accepted',
        );
      }
    });

    test('invalid relation_scope_key is rejected', () async {
      final src = await doc();
      final tgt = await doc();
      expect(
        () => relation(source: src, target: tgt, scope: 'total'),
        throwsA(isA<SqliteException>()),
      );
    });

    test('duplicate (source, target, type) is rejected', () async {
      final src = await doc();
      final tgt = await doc();
      await relation(source: src, target: tgt);
      expect(
        () => relation(source: src, target: tgt),
        throwsA(isA<SqliteException>()),
      );
    });

    test('same pair with different type is allowed', () async {
      final src = await doc();
      final tgt = await doc();
      await relation(source: src, target: tgt, type: 'repeals');
      await expectLater(
        relation(source: src, target: tgt, type: 'amends'),
        completes,
      );
    });

    test('source and target FK to documents.id', () async {
      expect(
        () => db
            .into(db.legislationRelations)
            .insert(
              LegislationRelationsCompanion.insert(
                sourceDocumentId: 9999,
                targetDocumentId: 9998,
                relationTypeKey: 'repeals',
                createdAt: now,
                updatedAt: now,
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('relation_scope_key defaults to unknown when omitted', () async {
      final src = await doc();
      final tgt = await doc();
      final id = await db
          .into(db.legislationRelations)
          .insert(
            LegislationRelationsCompanion.insert(
              sourceDocumentId: src,
              targetDocumentId: tgt,
              relationTypeKey: 'amends',
              createdAt: now,
              updatedAt: now,
            ),
          );
      final row = await (db.select(
        db.legislationRelations,
      )..where((r) => r.id.equals(id))).getSingle();
      expect(row.relationScopeKey, 'unknown');
    });

    test(
      'deleting source document is restricted when relation exists',
      () async {
        final src = await doc();
        final tgt = await doc();
        await relation(source: src, target: tgt);
        expect(
          () => (db.delete(db.documents)..where((d) => d.id.equals(src))).go(),
          throwsA(isA<SqliteException>()),
        );
      },
    );

    test('three performance indexes exist on legislation_relations', () async {
      final indexes =
          (await db
                  .customSelect(
                    "SELECT name FROM sqlite_master WHERE type='index' "
                    "AND tbl_name='legislation_relations';",
                  )
                  .get())
              .map((r) => r.read<String>('name'))
              .toSet();
      expect(indexes, contains('idx_lr_source'));
      expect(indexes, contains('idx_lr_target'));
      expect(indexes, contains('idx_lr_type'));
    });
  });

  group('legislation_details v6 new columns', () {
    late AppDatabase db;
    const String now = '2026-06-29T10:00:00Z';

    setUp(() async {
      db = AppDatabase.inMemory();
      await ReferenceSeeder(db).seedAll();
    });

    tearDown(() => db.close());

    Future<int> doc() => db
        .into(db.documents)
        .insert(DocumentsCompanion.insert(createdAt: now, updatedAt: now));

    test('new columns accept values', () async {
      final d = await doc();
      await db
          .into(db.legislationDetails)
          .insert(
            LegislationDetailsCompanion.insert(
              documentId: d,
              legislationNumber: const Value('42'),
              legislationYear: const Value(2024),
              effectiveDate: const Value('2024-01-01'),
              repealDate: const Value('2025-12-31'),
            ),
          );
      final row = await (db.select(
        db.legislationDetails,
      )..where((r) => r.documentId.equals(d))).getSingle();
      expect(row.legislationNumber, '42');
      expect(row.legislationYear, 2024);
      expect(row.effectiveDate, '2024-01-01');
      expect(row.repealDate, '2025-12-31');
    });

    test('new columns accept NULL', () async {
      final d = await doc();
      await db
          .into(db.legislationDetails)
          .insert(LegislationDetailsCompanion.insert(documentId: d));
      final row = await (db.select(
        db.legislationDetails,
      )..where((r) => r.documentId.equals(d))).getSingle();
      expect(row.legislationNumber, isNull);
      expect(row.legislationYear, isNull);
      expect(row.effectiveDate, isNull);
      expect(row.repealDate, isNull);
    });

    test(
      "'amended' and 'expired' are valid effective_status_key values",
      () async {
        for (final status in const ['amended', 'expired']) {
          final d = await doc();
          await expectLater(
            db
                .into(db.legislationDetails)
                .insert(
                  LegislationDetailsCompanion.insert(
                    documentId: d,
                    effectiveStatusKey: Value(status),
                  ),
                ),
            completes,
            reason: 'status=$status should be accepted',
          );
        }
      },
    );
  });
}
