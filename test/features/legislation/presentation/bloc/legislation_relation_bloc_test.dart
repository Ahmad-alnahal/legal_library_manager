import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/database/seeding/reference_seeder.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/features/legislation/data/repositories/drift_legislation_relation_repository.dart';
import 'package:legal_library_manager/features/legislation/domain/entities/legislation_relation_input.dart';
import 'package:legal_library_manager/features/legislation/domain/entities/legislation_relation_scope.dart';
import 'package:legal_library_manager/features/legislation/domain/entities/legislation_relation_type.dart';
import 'package:legal_library_manager/features/legislation/domain/usecases/create_legislation_relation.dart';
import 'package:legal_library_manager/features/legislation/domain/usecases/delete_legislation_relation.dart';
import 'package:legal_library_manager/features/legislation/domain/usecases/list_incoming_relations.dart';
import 'package:legal_library_manager/features/legislation/domain/usecases/list_outgoing_relations.dart';
import 'package:legal_library_manager/features/legislation/presentation/bloc/legislation_relation_bloc.dart';
import 'package:legal_library_manager/features/legislation/presentation/bloc/legislation_relation_event.dart';
import 'package:legal_library_manager/features/legislation/presentation/bloc/legislation_relation_state.dart';

// A fixed-time clock for tests.
class _FixedClock extends Clock {
  const _FixedClock();
  @override
  DateTime nowUtc() => DateTime.utc(2026, 6, 29, 12, 0, 0);
}

void main() {
  late AppDatabase db;
  late LegislationRelationBloc bloc;
  const nowIso = '2026-06-29T12:00:00.000Z';

  setUp(() async {
    db = AppDatabase.inMemory();
    await ReferenceSeeder(db).seedAll();
    final repo = DriftLegislationRelationRepository(db);
    bloc = LegislationRelationBloc(
      listOutgoing: ListOutgoingRelations(repo),
      listIncoming: ListIncomingRelations(repo),
      createRelation: CreateLegislationRelation(repo),
      deleteRelation: DeleteLegislationRelation(repo),
      clock: const _FixedClock(),
    );
  });

  tearDown(() async {
    await bloc.close();
    await db.close();
  });

  Future<int> insertDoc() => db
      .into(db.documents)
      .insert(DocumentsCompanion.insert(createdAt: nowIso, updatedAt: nowIso));

  group('LegislationRelationBloc', () {
    test('initial state has status=initial and empty lists', () {
      expect(bloc.state.status, LegislationRelationStatus.initial);
      expect(bloc.state.outgoing, isEmpty);
      expect(bloc.state.incoming, isEmpty);
      expect(bloc.state.error, isNull);
    });

    test(
      'LegislationRelationsLoaded emits success with empty lists for new document',
      () async {
        final docId = await insertDoc();
        bloc.add(LegislationRelationsLoaded(docId));

        final states = await bloc.stream.take(2).toList(); // loading + success

        expect(states.first.status, LegislationRelationStatus.loading);
        expect(states.last.status, LegislationRelationStatus.success);
        expect(states.last.outgoing, isEmpty);
        expect(states.last.incoming, isEmpty);
      },
    );

    test('LegislationRelationCreateRequested creates and reloads', () async {
      final src = await insertDoc();
      final tgt = await insertDoc();

      bloc.add(LegislationRelationsLoaded(src));
      await bloc.stream.firstWhere(
        (s) => s.status == LegislationRelationStatus.success,
      );

      bloc.add(
        LegislationRelationCreateRequested(
          documentId: src,
          input: LegislationRelationInput(
            sourceDocumentId: src,
            targetDocumentId: tgt,
            relationType: LegislationRelationType.repeals,
            relationScope: LegislationRelationScope.full,
          ),
        ),
      );

      final state = await bloc.stream.firstWhere(
        (s) =>
            s.status == LegislationRelationStatus.success &&
            s.outgoing.isNotEmpty,
      );

      expect(state.outgoing, hasLength(1));
      expect(
        state.outgoing.first.relationType,
        LegislationRelationType.repeals,
      );
      expect(state.outgoing.first.sourceDocumentId, src);
      expect(state.outgoing.first.targetDocumentId, tgt);
      expect(state.incoming, isEmpty);
    });

    test('LegislationRelationDeleteRequested deletes and reloads', () async {
      final src = await insertDoc();
      final tgt = await insertDoc();

      // Pre-create a relation.
      final repo = DriftLegislationRelationRepository(db);
      final rel = await repo.createRelation(
        LegislationRelationInput(
          sourceDocumentId: src,
          targetDocumentId: tgt,
          relationType: LegislationRelationType.amends,
        ),
        now: const _FixedClock().nowUtc(),
      );

      bloc.add(LegislationRelationsLoaded(src));
      await bloc.stream.firstWhere(
        (s) =>
            s.status == LegislationRelationStatus.success &&
            s.outgoing.isNotEmpty,
      );

      bloc.add(
        LegislationRelationDeleteRequested(documentId: src, relationId: rel.id),
      );

      final state = await bloc.stream.firstWhere(
        (s) =>
            s.status == LegislationRelationStatus.success && s.outgoing.isEmpty,
      );

      expect(state.outgoing, isEmpty);
    });

    test('self-relation create sets error state', () async {
      final docId = await insertDoc();

      bloc.add(LegislationRelationsLoaded(docId));
      await bloc.stream.firstWhere(
        (s) => s.status == LegislationRelationStatus.success,
      );

      bloc.add(
        LegislationRelationCreateRequested(
          documentId: docId,
          input: LegislationRelationInput(
            sourceDocumentId: docId,
            targetDocumentId: docId,
            relationType: LegislationRelationType.repeals,
          ),
        ),
      );

      final state = await bloc.stream.firstWhere((s) => s.error != null);
      expect(state.error, isNotNull);
    });

    test('incoming relations are loaded for target document', () async {
      final src = await insertDoc();
      final tgt = await insertDoc();

      bloc.add(LegislationRelationsLoaded(tgt));
      await bloc.stream.firstWhere(
        (s) => s.status == LegislationRelationStatus.success,
      );

      // Create relation via bloc (src → tgt) using tgt's bloc won't work
      // directly; use repo directly.
      final repo = DriftLegislationRelationRepository(db);
      await repo.createRelation(
        LegislationRelationInput(
          sourceDocumentId: src,
          targetDocumentId: tgt,
          relationType: LegislationRelationType.supersedes,
        ),
        now: const _FixedClock().nowUtc(),
      );

      // Reload.
      bloc.add(LegislationRelationsLoaded(tgt));
      final state = await bloc.stream.firstWhere(
        (s) =>
            s.status == LegislationRelationStatus.success &&
            s.incoming.isNotEmpty,
      );

      expect(state.incoming, hasLength(1));
      expect(
        state.incoming.first.relationType,
        LegislationRelationType.supersedes,
      );
      expect(state.outgoing, isEmpty);
    });

    test('loaded relations include target document title and code', () async {
      final src = await db
          .into(db.documents)
          .insert(
            DocumentsCompanion.insert(
              createdAt: nowIso,
              updatedAt: nowIso,
              title: const Value('Source Law'),
              documentCode: const Value('SRC-001'),
            ),
          );
      final tgt = await db
          .into(db.documents)
          .insert(
            DocumentsCompanion.insert(
              createdAt: nowIso,
              updatedAt: nowIso,
              title: const Value('Target Law'),
              documentCode: const Value('TGT-002'),
            ),
          );

      final repo = DriftLegislationRelationRepository(db);
      await repo.createRelation(
        LegislationRelationInput(
          sourceDocumentId: src,
          targetDocumentId: tgt,
          relationType: LegislationRelationType.repeals,
        ),
        now: const _FixedClock().nowUtc(),
      );

      bloc.add(LegislationRelationsLoaded(src));
      final state = await bloc.stream.firstWhere(
        (s) =>
            s.status == LegislationRelationStatus.success &&
            s.outgoing.isNotEmpty,
      );

      expect(state.outgoing.first.targetDocumentTitle, 'Target Law');
      expect(state.outgoing.first.targetDocumentCode, 'TGT-002');
      expect(state.outgoing.first.sourceDocumentTitle, 'Source Law');
      expect(state.outgoing.first.sourceDocumentCode, 'SRC-001');
    });

    test('relation tile falls back to code when title is null', () async {
      final src = await db
          .into(db.documents)
          .insert(
            DocumentsCompanion.insert(
              createdAt: nowIso,
              updatedAt: nowIso,
              documentCode: const Value('NOTITLE-001'),
            ),
          );
      final tgt = await db
          .into(db.documents)
          .insert(
            DocumentsCompanion.insert(
              createdAt: nowIso,
              updatedAt: nowIso,
              documentCode: const Value('NOTITLE-002'),
            ),
          );

      final repo = DriftLegislationRelationRepository(db);
      await repo.createRelation(
        LegislationRelationInput(
          sourceDocumentId: src,
          targetDocumentId: tgt,
          relationType: LegislationRelationType.amends,
        ),
        now: const _FixedClock().nowUtc(),
      );

      bloc.add(LegislationRelationsLoaded(src));
      final state = await bloc.stream.firstWhere(
        (s) =>
            s.status == LegislationRelationStatus.success &&
            s.outgoing.isNotEmpty,
      );

      expect(state.outgoing.first.targetDocumentTitle, isNull);
      expect(state.outgoing.first.targetDocumentCode, 'NOTITLE-002');
    });
  });
}
