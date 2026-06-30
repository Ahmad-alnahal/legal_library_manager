import '../entities/legislation_relation.dart';
import '../repositories/legislation_relation_repository.dart';

/// Returns all relations where [documentId] is the target.
class ListIncomingRelations {
  const ListIncomingRelations(this._repository);

  final LegislationRelationRepository _repository;

  Future<List<LegislationRelation>> call(int documentId) =>
      _repository.listIncomingRelations(documentId);
}
