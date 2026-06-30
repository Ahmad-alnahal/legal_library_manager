// ignore_for_file: recursive_getters
import 'package:drift/drift.dart';

import 'documents.dart';

/// Normalized relation between two legislation documents (Pre-P3 schema v6).
///
/// The unique constraint (source, target, relation_type) prevents duplicate
/// relations. Self-relations are rejected by [CreateLegislationRelation] at
/// the use-case level; SQLite cannot express a cross-column CHECK without
/// triggers.
///
/// [DataClassName] is 'LegislationRelationRow' to avoid a name clash with the
/// domain entity [LegislationRelation].
@DataClassName('LegislationRelationRow')
class LegislationRelations extends Table {
  @override
  String get tableName => 'legislation_relations';

  IntColumn get id => integer().autoIncrement()();

  IntColumn get sourceDocumentId =>
      integer().references(Documents, #id, onDelete: KeyAction.restrict)();

  IntColumn get targetDocumentId =>
      integer().references(Documents, #id, onDelete: KeyAction.restrict)();

  TextColumn get relationTypeKey => text().check(
    relationTypeKey.isIn(const [
      'repeals',
      'amends',
      'implements',
      'based_on',
      'supersedes',
    ]),
  )();

  TextColumn get relationScopeKey => text()
      .withDefault(const Constant('unknown'))
      .check(relationScopeKey.isIn(const ['full', 'partial', 'unknown']))();

  TextColumn get effectiveDate => text().nullable()();
  TextColumn get notes => text().nullable()();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();

  @override
  List<Set<Column>> get uniqueKeys => [
    {sourceDocumentId, targetDocumentId, relationTypeKey},
  ];
}
