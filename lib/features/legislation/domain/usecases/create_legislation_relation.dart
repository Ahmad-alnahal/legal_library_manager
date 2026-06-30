import '../entities/legislation_relation.dart';
import '../entities/legislation_relation_input.dart';
import '../repositories/legislation_relation_repository.dart';

/// Creates a legislation relation after validating there is no self-relation.
///
/// The database unique constraint prevents duplicate (source, target, type)
/// triples; this use case adds the domain-level guard that source ≠ target.
class CreateLegislationRelation {
  const CreateLegislationRelation(this._repository);

  final LegislationRelationRepository _repository;

  Future<LegislationRelation> call(
    LegislationRelationInput input, {
    required DateTime now,
  }) {
    if (input.sourceDocumentId == input.targetDocumentId) {
      throw ArgumentError(
        'sourceDocumentId and targetDocumentId must differ; '
        'a document cannot have a relation to itself.',
      );
    }
    return _repository.createRelation(input, now: now);
  }
}
