import 'package:equatable/equatable.dart';

import 'legislation_relation_scope.dart';
import 'legislation_relation_type.dart';

/// Value object used to create a new legislation relation.
class LegislationRelationInput extends Equatable {
  const LegislationRelationInput({
    required this.sourceDocumentId,
    required this.targetDocumentId,
    required this.relationType,
    this.relationScope = LegislationRelationScope.unknown,
    this.effectiveDate,
    this.notes,
  });

  final int sourceDocumentId;
  final int targetDocumentId;
  final LegislationRelationType relationType;
  final LegislationRelationScope relationScope;
  final String? effectiveDate;
  final String? notes;

  @override
  List<Object?> get props => [
    sourceDocumentId,
    targetDocumentId,
    relationType,
    relationScope,
    effectiveDate,
    notes,
  ];
}
