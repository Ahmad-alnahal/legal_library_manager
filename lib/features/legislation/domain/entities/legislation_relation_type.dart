/// The directional relationship a source legislation has with a target.
///
/// [key] matches the `relation_type_key` stored in `legislation_relations`.
/// The UI derives reverse wording from the key (e.g. 'repeals' →
/// 'ألغي بموجب' on the target side).
///
/// Note: the enum value [implementing] uses key `'implements'` because
/// `implements` is a Dart reserved word.
enum LegislationRelationType {
  repeals('repeals'),
  amends('amends'),
  implementing('implements'),
  basedOn('based_on'),
  supersedes('supersedes');

  const LegislationRelationType(this.key);

  final String key;

  static LegislationRelationType fromKey(String key) {
    return values.firstWhere(
      (e) => e.key == key,
      orElse: () =>
          throw ArgumentError('Unknown LegislationRelationType key: $key'),
    );
  }
}
