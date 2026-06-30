import '../entities/legislation_relation.dart';
import '../repositories/legislation_relation_repository.dart';

/// Returns all relations where [documentId] is the source.
class ListOutgoingRelations {
  const ListOutgoingRelations(this._repository);

  final LegislationRelationRepository _repository;

  Future<List<LegislationRelation>> call(int documentId) =>
      _repository.listOutgoingRelations(documentId);
}
