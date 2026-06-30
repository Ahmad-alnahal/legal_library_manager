import '../entities/legislation_relation.dart';
import '../entities/legislation_relation_input.dart';

/// Persistence contract for legislation relations.
///
/// Implementations live in the data layer and may import Drift; this interface
/// must not import Drift or Flutter.
abstract class LegislationRelationRepository {
  Future<LegislationRelation> createRelation(
    LegislationRelationInput input, {
    required DateTime now,
  });

  Future<List<LegislationRelation>> listOutgoingRelations(int documentId);

  Future<List<LegislationRelation>> listIncomingRelations(int documentId);

  Future<void> deleteRelation(int relationId);
}
