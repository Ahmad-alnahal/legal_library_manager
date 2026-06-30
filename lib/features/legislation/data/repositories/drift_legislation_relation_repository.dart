import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/entities/legislation_relation.dart';
import '../../domain/entities/legislation_relation_input.dart';
import '../../domain/entities/legislation_relation_scope.dart';
import '../../domain/entities/legislation_relation_type.dart';
import '../../domain/repositories/legislation_relation_repository.dart';

class DriftLegislationRelationRepository
    implements LegislationRelationRepository {
  const DriftLegislationRelationRepository(this._db);

  final AppDatabase _db;

  @override
  Future<LegislationRelation> createRelation(
    LegislationRelationInput input, {
    required DateTime now,
  }) async {
    final nowIso = now.toIso8601String();
    final id = await _db
        .into(_db.legislationRelations)
        .insert(
          LegislationRelationsCompanion.insert(
            sourceDocumentId: input.sourceDocumentId,
            targetDocumentId: input.targetDocumentId,
            relationTypeKey: input.relationType.key,
            relationScopeKey: Value(input.relationScope.key),
            effectiveDate: Value(input.effectiveDate),
            notes: Value(input.notes),
            createdAt: nowIso,
            updatedAt: nowIso,
          ),
        );
    return _rowToEntity(
      await (_db.select(
        _db.legislationRelations,
      )..where((r) => r.id.equals(id))).getSingle(),
    );
  }

  @override
  Future<List<LegislationRelation>> listOutgoingRelations(
    int documentId,
  ) async {
    return _queryWithDocuments(
      'SELECT lr.*, src.title AS source_title, src.document_code AS source_code,'
      ' tgt.title AS target_title, tgt.document_code AS target_code'
      ' FROM legislation_relations lr'
      ' LEFT JOIN documents src ON src.id = lr.source_document_id'
      ' LEFT JOIN documents tgt ON tgt.id = lr.target_document_id'
      ' WHERE lr.source_document_id = ?'
      ' ORDER BY lr.created_at ASC',
      [documentId],
    );
  }

  @override
  Future<List<LegislationRelation>> listIncomingRelations(
    int documentId,
  ) async {
    return _queryWithDocuments(
      'SELECT lr.*, src.title AS source_title, src.document_code AS source_code,'
      ' tgt.title AS target_title, tgt.document_code AS target_code'
      ' FROM legislation_relations lr'
      ' LEFT JOIN documents src ON src.id = lr.source_document_id'
      ' LEFT JOIN documents tgt ON tgt.id = lr.target_document_id'
      ' WHERE lr.target_document_id = ?'
      ' ORDER BY lr.created_at ASC',
      [documentId],
    );
  }

  Future<List<LegislationRelation>> _queryWithDocuments(
    String sql,
    List<Object?> args,
  ) async {
    final rows = await _db
        .customSelect(sql, variables: [for (final a in args) Variable(a)])
        .get();
    return rows.map(_enrichedRowToEntity).toList(growable: false);
  }

  LegislationRelation _enrichedRowToEntity(QueryRow row) {
    return LegislationRelation(
      id: row.read<int>('id'),
      sourceDocumentId: row.read<int>('source_document_id'),
      targetDocumentId: row.read<int>('target_document_id'),
      relationType: LegislationRelationType.fromKey(
        row.read<String>('relation_type_key'),
      ),
      relationScope: LegislationRelationScope.fromKey(
        row.read<String>('relation_scope_key'),
      ),
      effectiveDate: row.readNullable<String>('effective_date'),
      notes: row.readNullable<String>('notes'),
      createdAt: DateTime.parse(row.read<String>('created_at')),
      updatedAt: DateTime.parse(row.read<String>('updated_at')),
      sourceDocumentTitle: row.readNullable<String>('source_title'),
      sourceDocumentCode: row.readNullable<String>('source_code'),
      targetDocumentTitle: row.readNullable<String>('target_title'),
      targetDocumentCode: row.readNullable<String>('target_code'),
    );
  }

  @override
  Future<void> deleteRelation(int relationId) async {
    await (_db.delete(
      _db.legislationRelations,
    )..where((r) => r.id.equals(relationId))).go();
  }

  LegislationRelation _rowToEntity(LegislationRelationRow row) {
    return LegislationRelation(
      id: row.id,
      sourceDocumentId: row.sourceDocumentId,
      targetDocumentId: row.targetDocumentId,
      relationType: LegislationRelationType.fromKey(row.relationTypeKey),
      relationScope: LegislationRelationScope.fromKey(row.relationScopeKey),
      effectiveDate: row.effectiveDate,
      notes: row.notes,
      createdAt: DateTime.parse(row.createdAt),
      updatedAt: DateTime.parse(row.updatedAt),
    );
  }
}
