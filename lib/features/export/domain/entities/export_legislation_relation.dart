// lib/features/export/domain/entities/export_legislation_relation.dart

import 'package:equatable/equatable.dart';

/// Website-safe outgoing legislation relation for one exported document.
class ExportLegislationRelation extends Equatable {
  const ExportLegislationRelation({
    required this.targetDocumentCode,
    required this.relationTypeKey,
    required this.scope,
    required this.effectiveDate,
    required this.notes,
  });

  final String targetDocumentCode;
  final String relationTypeKey;
  final String? scope;
  final String? effectiveDate;
  final String? notes;

  @override
  List<Object?> get props => [
    targetDocumentCode,
    relationTypeKey,
    scope,
    effectiveDate,
    notes,
  ];
}
