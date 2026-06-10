// lib/features/categories/data/repositories/drift_category_management_repository.dart

import 'package:drift/drift.dart';
import 'package:sqlite3/common.dart' show SqliteException;

import '../../../../core/database/app_database.dart';
import '../../../../core/validation/category_name.dart';
import '../../domain/entities/managed_main_category.dart';
import '../../domain/entities/managed_sub_category.dart';
import '../../domain/repositories/category_management_repository.dart';

/// Prepared display + normalized values for a write.
typedef _PreparedNames = ({
  String displayAr,
  String displayEn,
  String normAr,
  String normEn,
});

/// Drift-backed [CategoryManagementRepository].
///
/// All Drift types stay inside this class. Every check-then-write runs inside a
/// single transaction so a failed integrity check rolls back cleanly and so
/// concurrent writes (serialized on the single connection) cannot interleave a
/// duplicate. Sort order is managed internally: inserts place the new row last
/// by computing MAX(sort_order)+1 inside the transaction; edits preserve the
/// existing sort order; reorder swaps two items and resequences the collection.
/// The friendly pre-write name comparison runs first; the SQLite unique indexes
/// on the normalized columns are the final backstop. Display and normalized
/// names are always written together. No method deletes a row or touches a file.
class DriftCategoryManagementRepository
    implements CategoryManagementRepository {
  DriftCategoryManagementRepository(this._db);

  final AppDatabase _db;

  @override
  Future<List<ManagedMainCategory>> getMainCategories() async {
    final rows =
        await (_db.select(_db.mainCategories)..orderBy([
              (t) => OrderingTerm(expression: t.sortOrder),
              (t) => OrderingTerm(expression: t.key),
            ]))
            .get();
    return rows
        .map(
          (r) => ManagedMainCategory(
            id: r.id,
            key: r.key,
            nameAr: r.nameAr,
            nameEn: r.nameEn,
            sortOrder: r.sortOrder,
            isActive: r.isActive,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<List<ManagedSubCategory>> getSubCategories({
    int? mainCategoryId,
  }) async {
    final query = _db.select(_db.subCategories)
      ..orderBy([
        (t) => OrderingTerm(expression: t.sortOrder),
        (t) => OrderingTerm(expression: t.key),
      ]);
    if (mainCategoryId != null) {
      query.where((t) => t.mainCategoryId.equals(mainCategoryId));
    }
    final rows = await query.get();
    return rows
        .map(
          (r) => ManagedSubCategory(
            id: r.id,
            mainCategoryId: r.mainCategoryId,
            key: r.key,
            nameAr: r.nameAr,
            nameEn: r.nameEn,
            sortOrder: r.sortOrder,
            isActive: r.isActive,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<int> insertMainCategory({
    required String key,
    required String nameAr,
    required String nameEn,
  }) {
    final _PreparedNames p = _prepare(nameAr, nameEn);
    return _runWrite(() {
      return _db.transaction(() async {
        final existing = await _db.select(_db.mainCategories).get();
        _ensureUniqueNames(
          existing.map((e) => (nameAr: e.nameAr, nameEn: e.nameEn)),
          p,
        );
        await _ensureKeyFree(key);
        final int nextSort =
            existing.fold(
              0,
              (max, e) => e.sortOrder > max ? e.sortOrder : max,
            ) +
            1;
        return _db
            .into(_db.mainCategories)
            .insert(
              MainCategoriesCompanion.insert(
                key: key,
                nameAr: p.displayAr,
                nameEn: p.displayEn,
                normalizedNameAr: p.normAr,
                normalizedNameEn: p.normEn,
                sortOrder: nextSort,
                isActive: true,
              ),
            );
      });
    });
  }

  @override
  Future<int> insertSubCategory({
    required int mainCategoryId,
    required String key,
    required String nameAr,
    required String nameEn,
  }) {
    final _PreparedNames p = _prepare(nameAr, nameEn);
    return _runWrite(() {
      return _db.transaction(() async {
        await _ensureActiveMainCategory(mainCategoryId);
        final siblings = await (_db.select(
          _db.subCategories,
        )..where((t) => t.mainCategoryId.equals(mainCategoryId))).get();
        _ensureUniqueNames(
          siblings.map((e) => (nameAr: e.nameAr, nameEn: e.nameEn)),
          p,
        );
        await _ensureKeyFree(key);
        final int nextSort =
            siblings.fold(
              0,
              (max, e) => e.sortOrder > max ? e.sortOrder : max,
            ) +
            1;
        return _db
            .into(_db.subCategories)
            .insert(
              SubCategoriesCompanion.insert(
                mainCategoryId: mainCategoryId,
                key: key,
                nameAr: p.displayAr,
                nameEn: p.displayEn,
                normalizedNameAr: p.normAr,
                normalizedNameEn: p.normEn,
                sortOrder: nextSort,
                isActive: true,
              ),
            );
      });
    });
  }

  @override
  Future<void> updateMainCategory({
    required int id,
    required String nameAr,
    required String nameEn,
  }) {
    final _PreparedNames p = _prepare(nameAr, nameEn);
    return _runWrite(() {
      return _db.transaction(() async {
        final others = await (_db.select(
          _db.mainCategories,
        )..where((t) => t.id.equals(id).not())).get();
        _ensureUniqueNames(
          others.map((e) => (nameAr: e.nameAr, nameEn: e.nameEn)),
          p,
        );
        await (_db.update(
          _db.mainCategories,
        )..where((t) => t.id.equals(id))).write(
          MainCategoriesCompanion(
            nameAr: Value(p.displayAr),
            nameEn: Value(p.displayEn),
            normalizedNameAr: Value(p.normAr),
            normalizedNameEn: Value(p.normEn),
            // sortOrder deliberately omitted — preserved
          ),
        );
      });
    });
  }

  @override
  Future<void> updateSubCategory({
    required int id,
    required String nameAr,
    required String nameEn,
  }) {
    final _PreparedNames p = _prepare(nameAr, nameEn);
    return _runWrite(() {
      return _db.transaction(() async {
        final row = await (_db.select(
          _db.subCategories,
        )..where((t) => t.id.equals(id))).getSingle();
        final siblings =
            await (_db.select(_db.subCategories)..where(
                  (t) =>
                      t.mainCategoryId.equals(row.mainCategoryId) &
                      t.id.equals(id).not(),
                ))
                .get();
        _ensureUniqueNames(
          siblings.map((e) => (nameAr: e.nameAr, nameEn: e.nameEn)),
          p,
        );
        await (_db.update(
          _db.subCategories,
        )..where((t) => t.id.equals(id))).write(
          SubCategoriesCompanion(
            nameAr: Value(p.displayAr),
            nameEn: Value(p.displayEn),
            normalizedNameAr: Value(p.normAr),
            normalizedNameEn: Value(p.normEn),
            // sortOrder deliberately omitted — preserved
          ),
        );
      });
    });
  }

  @override
  Future<void> setMainCategoryActive(int id, {required bool isActive}) async {
    await (_db.update(_db.mainCategories)..where((t) => t.id.equals(id))).write(
      MainCategoriesCompanion(isActive: Value(isActive)),
    );
  }

  @override
  Future<void> setSubCategoryActive(int id, {required bool isActive}) async {
    await (_db.update(_db.subCategories)..where((t) => t.id.equals(id))).write(
      SubCategoriesCompanion(isActive: Value(isActive)),
    );
  }

  @override
  Future<void> moveSubCategory({
    required int subCategoryId,
    required int newMainCategoryId,
  }) {
    return _runWrite(() {
      return _db.transaction(() async {
        final row = await (_db.select(
          _db.subCategories,
        )..where((t) => t.id.equals(subCategoryId))).getSingle();
        if (row.mainCategoryId == newMainCategoryId) return;

        await _ensureActiveMainCategory(newMainCategoryId);
        if (await _isSubCategoryUsed(subCategoryId)) {
          throw const SubCategoryInUseException();
        }

        // The move keeps the subcategory's names, so reuse its stored
        // normalized values for the duplicate check under the target parent.
        final _PreparedNames p = (
          displayAr: row.nameAr,
          displayEn: row.nameEn,
          normAr: row.normalizedNameAr,
          normEn: row.normalizedNameEn,
        );
        final targetSiblings = await (_db.select(
          _db.subCategories,
        )..where((t) => t.mainCategoryId.equals(newMainCategoryId))).get();
        _ensureUniqueNames(
          targetSiblings.map((e) => (nameAr: e.nameAr, nameEn: e.nameEn)),
          p,
        );

        // Place last in the target collection.
        final int nextSort =
            targetSiblings.fold(
              0,
              (max, e) => e.sortOrder > max ? e.sortOrder : max,
            ) +
            1;
        final int sourceMainId = row.mainCategoryId;

        await (_db.update(
          _db.subCategories,
        )..where((t) => t.id.equals(subCategoryId))).write(
          SubCategoriesCompanion(
            mainCategoryId: Value(newMainCategoryId),
            sortOrder: Value(nextSort),
          ),
        );

        // Resequence both source and target so positions remain gapless.
        await _resequenceSubCategories(sourceMainId);
        await _resequenceSubCategories(newMainCategoryId);
      });
    });
  }

  @override
  Future<bool> isSubCategoryUsed(int subCategoryId) =>
      _isSubCategoryUsed(subCategoryId);

  @override
  Future<void> reorderMainCategory({required int idA, required int idB}) {
    return _runWrite(() {
      return _db.transaction(() async {
        final rows =
            await (_db.select(_db.mainCategories)..orderBy([
                  (t) => OrderingTerm(expression: t.sortOrder),
                  (t) => OrderingTerm(expression: t.key),
                ]))
                .get();
        final int indexA = rows.indexWhere((r) => r.id == idA);
        final int indexB = rows.indexWhere((r) => r.id == idB);
        if (indexA < 0 || indexB < 0) return; // ids not found — no-op

        // Transpose the two items in the Dart list, then write sequential
        // positions for the full collection.
        final reordered = List.of(rows);
        final temp = reordered[indexA];
        reordered[indexA] = reordered[indexB];
        reordered[indexB] = temp;

        for (var i = 0; i < reordered.length; i++) {
          await (_db.update(_db.mainCategories)
                ..where((t) => t.id.equals(reordered[i].id)))
              .write(MainCategoriesCompanion(sortOrder: Value(i + 1)));
        }
      });
    });
  }

  @override
  Future<void> reorderSubCategory({required int idA, required int idB}) {
    return _runWrite(() {
      return _db.transaction(() async {
        final rowA = await (_db.select(
          _db.subCategories,
        )..where((t) => t.id.equals(idA))).getSingleOrNull();
        if (rowA == null) return;

        final rows =
            await (_db.select(_db.subCategories)
                  ..where((t) => t.mainCategoryId.equals(rowA.mainCategoryId))
                  ..orderBy([
                    (t) => OrderingTerm(expression: t.sortOrder),
                    (t) => OrderingTerm(expression: t.key),
                  ]))
                .get();
        final int indexA = rows.indexWhere((r) => r.id == idA);
        final int indexB = rows.indexWhere((r) => r.id == idB);
        if (indexA < 0 || indexB < 0) return;

        final reordered = List.of(rows);
        final temp = reordered[indexA];
        reordered[indexA] = reordered[indexB];
        reordered[indexB] = temp;

        for (var i = 0; i < reordered.length; i++) {
          await (_db.update(_db.subCategories)
                ..where((t) => t.id.equals(reordered[i].id)))
              .write(SubCategoriesCompanion(sortOrder: Value(i + 1)));
        }
      });
    });
  }

  // --- internals ---

  Future<bool> _isSubCategoryUsed(int subCategoryId) async {
    final primaryCountExp = _db.documents.id.count();
    final primaryCount =
        await (_db.selectOnly(_db.documents)
              ..addColumns([primaryCountExp])
              ..where(_db.documents.primarySubCategoryId.equals(subCategoryId)))
            .map((row) => row.read(primaryCountExp))
            .getSingle();
    if ((primaryCount ?? 0) > 0) return true;

    final classCountExp = _db.documentClassifications.id.count();
    final classificationCount =
        await (_db.selectOnly(_db.documentClassifications)
              ..addColumns([classCountExp])
              ..where(
                _db.documentClassifications.subCategoryId.equals(subCategoryId),
              ))
            .map((row) => row.read(classCountExp))
            .getSingle();
    return (classificationCount ?? 0) > 0;
  }

  Future<void> _ensureKeyFree(String key) async {
    final mainHit = await (_db.select(
      _db.mainCategories,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    if (mainHit != null) throw const CategoryKeyCollisionException();
    final subHit = await (_db.select(
      _db.subCategories,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    if (subHit != null) throw const CategoryKeyCollisionException();
  }

  Future<void> _ensureActiveMainCategory(int id) async {
    final parent = await (_db.select(
      _db.mainCategories,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (parent == null || !parent.isActive) {
      throw const InactiveMainCategoryException();
    }
  }

  /// Cleans the incoming display names and derives their normalized comparison
  /// values, so the pair stored is always consistent regardless of the caller.
  _PreparedNames _prepare(String nameAr, String nameEn) {
    final String displayAr = cleanCategoryDisplayName(nameAr);
    final String displayEn = cleanCategoryDisplayName(nameEn);
    return (
      displayAr: displayAr,
      displayEn: displayEn,
      normAr: normalizedCategoryNameAr(displayAr),
      normEn: normalizedCategoryNameEn(displayEn),
    );
  }

  /// Friendly pre-write comparison against already-stored rows, using the shared
  /// language-specific normalization.
  void _ensureUniqueNames(
    Iterable<({String nameAr, String nameEn})> existing,
    _PreparedNames candidate,
  ) {
    for (final e in existing) {
      if (normalizedCategoryNameAr(e.nameAr) == candidate.normAr) {
        throw const DuplicateCategoryNameException('nameAr');
      }
      if (normalizedCategoryNameEn(e.nameEn) == candidate.normEn) {
        throw const DuplicateCategoryNameException('nameEn');
      }
    }
  }

  /// Resequences subcategories under [mainCategoryId] to gapless 1,2,3,...
  /// positions in the current sort order.
  Future<void> _resequenceSubCategories(int mainCategoryId) async {
    final rows =
        await (_db.select(_db.subCategories)
              ..where((t) => t.mainCategoryId.equals(mainCategoryId))
              ..orderBy([
                (t) => OrderingTerm(expression: t.sortOrder),
                (t) => OrderingTerm(expression: t.key),
              ]))
            .get();
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].sortOrder != i + 1) {
        await (_db.update(_db.subCategories)
              ..where((t) => t.id.equals(rows[i].id)))
            .write(SubCategoriesCompanion(sortOrder: Value(i + 1)));
      }
    }
  }

  /// Runs a write and translates a SQLite unique-constraint violation on the
  /// normalized-name indexes into the same safe [DuplicateCategoryNameException]
  /// the friendly pre-check would raise (race backstop). A key-uniqueness
  /// violation becomes a [CategoryKeyCollisionException]. The check is on the
  /// error text (and tolerant of drift wrapping a [SqliteException]); only a
  /// genuine unique-constraint failure is translated, everything else
  /// propagates unchanged.
  Future<T> _runWrite<T>(Future<T> Function() write) async {
    try {
      return await write();
    } catch (e) {
      if (e is DuplicateCategoryNameException ||
          e is CategoryKeyCollisionException ||
          e is SubCategoryInUseException ||
          e is InactiveMainCategoryException) {
        rethrow;
      }
      final String message = e.toString().toLowerCase();
      final bool isUniqueViolation =
          e is SqliteException || message.contains('unique constraint failed');
      if (isUniqueViolation) {
        if (message.contains('normalized_name_ar')) {
          throw const DuplicateCategoryNameException('nameAr');
        }
        if (message.contains('normalized_name_en')) {
          throw const DuplicateCategoryNameException('nameEn');
        }
        if (message.contains('.key')) {
          throw const CategoryKeyCollisionException();
        }
      }
      rethrow;
    }
  }
}
