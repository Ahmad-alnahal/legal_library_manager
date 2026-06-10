// lib/features/categories/domain/services/category_key_generator.dart

import 'dart:math';

/// Generates collision-resistant, immutable internal keys for user-created
/// categories. Keys are never derived from user-entered names (so renaming a
/// category never changes its key) and never collide with seeded keys, which
/// use plain human-readable identifiers like `public_law`.
abstract class CategoryKeyGenerator {
  /// A new immutable key for a user-created main category.
  String mainCategoryKey();

  /// A new immutable key for a user-created subcategory.
  String subCategoryKey();
}

/// Default generator: `usr_main_<base36-microseconds>_<base36-random>`.
///
/// The timestamp keeps keys roughly ordered and the random suffix makes
/// collisions astronomically unlikely even within the same microsecond. The
/// `usr_` prefix guarantees no overlap with seeded keys.
class DefaultCategoryKeyGenerator implements CategoryKeyGenerator {
  DefaultCategoryKeyGenerator({Random? random, DateTime Function()? now})
    : _random = random ?? Random.secure(),
      _now = now ?? DateTime.now;

  final Random _random;
  final DateTime Function() _now;

  String _key(String kind) {
    final int micros = _now().toUtc().microsecondsSinceEpoch;
    final int rand = _random.nextInt(1 << 32);
    return 'usr_${kind}_${micros.toRadixString(36)}_${rand.toRadixString(36)}';
  }

  @override
  String mainCategoryKey() => _key('main');

  @override
  String subCategoryKey() => _key('sub');
}
