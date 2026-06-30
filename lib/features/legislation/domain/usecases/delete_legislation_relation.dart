import '../repositories/legislation_relation_repository.dart';

/// Deletes a legislation relation by its primary key.
class DeleteLegislationRelation {
  const DeleteLegislationRelation(this._repository);

  final LegislationRelationRepository _repository;

  Future<void> call(int relationId) => _repository.deleteRelation(relationId);
}
