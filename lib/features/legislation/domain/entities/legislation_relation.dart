import 'package:equatable/equatable.dart';

import 'legislation_relation_scope.dart';
import 'legislation_relation_type.dart';

/// A persisted relation between two legislation documents (read model).
class LegislationRelation extends Equatable {
  const LegislationRelation({
    required this.id,
    required this.sourceDocumentId,
    required this.targetDocumentId,
    required this.relationType,
    required this.relationScope,
    this.effectiveDate,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
    this.sourceDocumentTitle,
    this.sourceDocumentCode,
    this.targetDocumentTitle,
    this.targetDocumentCode,
  });

  final int id;
  final int sourceDocumentId;
  final int targetDocumentId;
  final LegislationRelationType relationType;
  final LegislationRelationScope relationScope;
  final String? effectiveDate;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Display-only: populated by the repository via JOIN with documents table.
  final String? sourceDocumentTitle;
  final String? sourceDocumentCode;
  final String? targetDocumentTitle;
  final String? targetDocumentCode;

  @override
  List<Object?> get props => [
    id,
    sourceDocumentId,
    targetDocumentId,
    relationType,
    relationScope,
    effectiveDate,
    notes,
    createdAt,
    updatedAt,
    sourceDocumentTitle,
    sourceDocumentCode,
    targetDocumentTitle,
    targetDocumentCode,
  ];
}
