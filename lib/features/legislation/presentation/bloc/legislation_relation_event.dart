import 'package:equatable/equatable.dart';

import '../../domain/entities/legislation_relation_input.dart';

sealed class LegislationRelationEvent extends Equatable {
  const LegislationRelationEvent();

  @override
  List<Object?> get props => [];
}

class LegislationRelationsLoaded extends LegislationRelationEvent {
  const LegislationRelationsLoaded(this.documentId);

  final int documentId;

  @override
  List<Object?> get props => [documentId];
}

class LegislationRelationCreateRequested extends LegislationRelationEvent {
  const LegislationRelationCreateRequested({
    required this.documentId,
    required this.input,
  });

  final int documentId;
  final LegislationRelationInput input;

  @override
  List<Object?> get props => [documentId, input];
}

class LegislationRelationDeleteRequested extends LegislationRelationEvent {
  const LegislationRelationDeleteRequested({
    required this.documentId,
    required this.relationId,
  });

  final int documentId;
  final int relationId;

  @override
  List<Object?> get props => [documentId, relationId];
}
