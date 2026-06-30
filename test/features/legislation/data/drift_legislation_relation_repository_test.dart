import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/database/seeding/reference_seeder.dart';
import 'package:legal_library_manager/features/legislation/data/repositories/drift_legislation_relation_repository.dart';
import 'package:legal_library_manager/features/legislation/domain/entities/legislation_relation_input.dart';
import 'package:legal_library_manager/features/legislation/domain/entities/legislation_relation_scope.dart';
import 'package:legal_library_manager/features/legislation/domain/entities/legislation_relation_type.dart';
import 'package:sqlite3/common.dart';

void main() {
  group('DriftLegislationRelationRepository', () {
    late AppDatabase db;
    late DriftLegislationRelationRepository repo;
    final DateTime now = _kNow;
    const String nowIso = '2026-06-29T10:00:00.000Z';

    setUp(() async {
      db = AppDatabase.inMemory();
      await ReferenceSeeder(db).seedAll();
      repo = DriftLegislationRelationRepository(db);
    });

    tearDown(() => db.close());

    Future<int> doc() => db
        .into(db.documents)
        .insert(
          DocumentsCompanion.insert(createdAt: nowIso, updatedAt: nowIso),
        );

    LegislationRelationInput input({
      required int source,
      required int target,
      LegislationRelationType type = LegislationRelationType.repeals,
      LegislationRelationScope scope = LegislationRelationScope.full,
    }) => LegislationRelationInput(
      sourceDocumentId: source,
      targetDocumentId: target,
      relationType: type,
      relationScope: scope,
    );

    test('createRelation returns entity with correct fields', () async {
      final src = await doc();
      final tgt = await doc();
      final relation = await repo.createRelation(
        input(source: src, target: tgt),
        now: now,
      );

      expect(relation.id, greaterThan(0));
      expect(relation.sourceDocumentId, src);
      expect(relation.targetDocumentId, tgt);
      expect(relation.relationType, LegislationRelationType.repeals);
      expect(relation.relationScope, LegislationRelationScope.full);
      expect(relation.createdAt, now);
      expect(relation.updatedAt, now);
    });

    test(
      'listOutgoingRelations returns relations where source = documentId',
      () async {
        final src = await doc();
        final tgt1 = await doc();
        final tgt2 = await doc();
        await repo.createRelation(
          input(
            source: src,
            target: tgt1,
            type: LegislationRelationType.repeals,
          ),
          now: now,
        );
        await repo.createRelation(
          input(
            source: src,
            target: tgt2,
            type: LegislationRelationType.amends,
          ),
          now: now,
        );

        final outgoing = await repo.listOutgoingRelations(src);
        expect(outgoing, hasLength(2));
        expect(outgoing.every((r) => r.sourceDocumentId == src), isTrue);
      },
    );

    test(
      'listIncomingRelations returns relations where target = documentId',
      () async {
        final src1 = await doc();
        final src2 = await doc();
        final tgt = await doc();
        await repo.createRelation(
          input(source: src1, target: tgt),
          now: now,
        );
        await repo.createRelation(
          input(
            source: src2,
            target: tgt,
            type: LegislationRelationType.amends,
          ),
          now: now,
        );

        final incoming = await repo.listIncomingRelations(tgt);
        expect(incoming, hasLength(2));
        expect(incoming.every((r) => r.targetDocumentId == tgt), isTrue);
      },
    );

    test(
      'listOutgoingRelations returns empty for document with no relations',
      () async {
        final d = await doc();
        expect(await repo.listOutgoingRelations(d), isEmpty);
      },
    );

    test(
      'listIncomingRelations returns empty for document with no relations',
      () async {
        final d = await doc();
        expect(await repo.listIncomingRelations(d), isEmpty);
      },
    );

    test('duplicate (source, target, type) throws on second insert', () async {
      final src = await doc();
      final tgt = await doc();
      await repo.createRelation(
        input(source: src, target: tgt),
        now: now,
      );
      expect(
        () => repo.createRelation(
          input(source: src, target: tgt),
          now: now,
        ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('deleteRelation removes the row', () async {
      final src = await doc();
      final tgt = await doc();
      final relation = await repo.createRelation(
        input(source: src, target: tgt),
        now: now,
      );
      await repo.deleteRelation(relation.id);
      expect(await repo.listOutgoingRelations(src), isEmpty);
    });

    test('enum fields round-trip through the database', () async {
      final src = await doc();
      final tgt = await doc();
      final relation = await repo.createRelation(
        input(
          source: src,
          target: tgt,
          type: LegislationRelationType.basedOn,
          scope: LegislationRelationScope.partial,
        ),
        now: now,
      );
      expect(relation.relationType, LegislationRelationType.basedOn);
      expect(relation.relationScope, LegislationRelationScope.partial);
    });

    test("'implements' key round-trips through the database", () async {
      final src = await doc();
      final tgt = await doc();
      final relation = await repo.createRelation(
        input(
          source: src,
          target: tgt,
          type: LegislationRelationType.implementing,
        ),
        now: now,
      );
      expect(relation.relationType, LegislationRelationType.implementing);
      expect(relation.relationType.key, 'implements');
    });

    test('optional effectiveDate + notes are stored and returned', () async {
      final src = await doc();
      final tgt = await doc();
      final relation = await repo.createRelation(
        LegislationRelationInput(
          sourceDocumentId: src,
          targetDocumentId: tgt,
          relationType: LegislationRelationType.amends,
          effectiveDate: '2025-01-01',
          notes: 'partial amendment of article 5',
        ),
        now: now,
      );
      expect(relation.effectiveDate, '2025-01-01');
      expect(relation.notes, 'partial amendment of article 5');
    });

    test('outgoing results are ordered by createdAt ascending', () async {
      final src = await doc();
      final tgt1 = await doc();
      final tgt2 = await doc();
      final r1 = await repo.createRelation(
        input(source: src, target: tgt1, type: LegislationRelationType.repeals),
        now: now,
      );
      final r2 = await repo.createRelation(
        input(source: src, target: tgt2, type: LegislationRelationType.amends),
        now: now,
      );
      final outgoing = await repo.listOutgoingRelations(src);
      expect(outgoing.first.id, r1.id);
      expect(outgoing.last.id, r2.id);
    });
  });
}

final DateTime _kNow = DateTime.utc(2026, 6, 29, 10, 0, 0);
