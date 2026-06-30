/// How much of the target legislation the relation affects.
///
/// [key] matches the `relation_scope_key` stored in `legislation_relations`.
enum LegislationRelationScope {
  full('full'),
  partial('partial'),
  unknown('unknown');

  const LegislationRelationScope(this.key);

  final String key;

  static LegislationRelationScope fromKey(String key) {
    return values.firstWhere(
      (e) => e.key == key,
      orElse: () =>
          throw ArgumentError('Unknown LegislationRelationScope key: $key'),
    );
  }
}
