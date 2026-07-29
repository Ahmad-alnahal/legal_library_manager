// lib/features/reference/data/repositories/drift_reference_repository.dart

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/entities/document_type_ref.dart';
import '../../domain/entities/main_category_ref.dart';
import '../../domain/entities/reference_item.dart';
import '../../domain/entities/sub_category_ref.dart';
import '../../domain/repositories/reference_repository.dart';

/// Drift-backed, read-only implementation of [ReferenceRepository].
///
/// All Drift-specific types stay inside this data-layer class; callers receive
/// only domain entities. Every query returns active rows only, ordered
/// deterministically by `sort_order` then key/id. No mutation is exposed.
class DriftReferenceRepository implements ReferenceRepository {
  DriftReferenceRepository(this._db);

  final AppDatabase _db;

  @override
  Future<List<DocumentTypeRef>> getDocumentTypes() async {
    final rows =
        await (_db.select(_db.documentTypes)
              ..where((t) => t.isActive.equals(true))
              ..orderBy([
                (t) => OrderingTerm(expression: t.sortOrder),
                (t) => OrderingTerm(expression: t.key),
              ]))
            .get();
    return rows
        .map(
          (r) => DocumentTypeRef(
            id: r.id,
            key: r.key,
            nameAr: r.nameAr,
            nameEn: r.nameEn,
            sortOrder: r.sortOrder,
          ),
        )
        .toList();
  }

  @override
  Future<List<MainCategoryRef>> getMainCategories() async {
    final rows =
        await (_db.select(_db.mainCategories)
              ..where((t) => t.isActive.equals(true))
              ..orderBy([
                (t) => OrderingTerm(expression: t.sortOrder),
                (t) => OrderingTerm(expression: t.key),
              ]))
            .get();
    return rows
        .map(
          (r) => MainCategoryRef(
            id: r.id,
            key: r.key,
            nameAr: r.nameAr,
            nameEn: r.nameEn,
            sortOrder: r.sortOrder,
          ),
        )
        .toList();
  }

  @override
  Future<List<SubCategoryRef>> getSubCategories({
    int? mainCategoryId,
    String? mainCategoryKey,
  }) async {
    if (mainCategoryId != null && mainCategoryKey != null) {
      throw ArgumentError(
        'Provide at most one of mainCategoryId or mainCategoryKey, not both.',
      );
    }

    int? parentId = mainCategoryId;
    if (mainCategoryKey != null) {
      final parent = await (_db.select(
        _db.mainCategories,
      )..where((t) => t.key.equals(mainCategoryKey))).getSingleOrNull();
      if (parent == null) return const <SubCategoryRef>[];
      parentId = parent.id;
    }

    final rows =
        await (_db.select(_db.subCategories)
              ..where(
                (t) => parentId == null
                    ? t.isActive.equals(true)
                    : t.isActive.equals(true) &
                          t.mainCategoryId.equals(parentId),
              )
              ..orderBy([
                (t) => OrderingTerm(expression: t.sortOrder),
                (t) => OrderingTerm(expression: t.key),
              ]))
            .get();
    return rows
        .map(
          (r) => SubCategoryRef(
            id: r.id,
            mainCategoryId: r.mainCategoryId,
            key: r.key,
            nameAr: r.nameAr,
            nameEn: r.nameEn,
            sortOrder: r.sortOrder,
          ),
        )
        .toList();
  }

  @override
  Future<List<ReferenceItem>> getLanguages() async {
    final rows =
        await (_db.select(_db.languages)
              ..where((t) => t.isActive.equals(true))
              ..orderBy([
                (t) => OrderingTerm(expression: t.sortOrder),
                (t) => OrderingTerm(expression: t.key),
              ]))
            .get();
    return rows
        .map(
          (r) => ReferenceItem(
            key: r.key,
            nameAr: r.nameAr,
            nameEn: r.nameEn,
            sortOrder: r.sortOrder,
          ),
        )
        .toList();
  }

  @override
  Future<List<ReferenceItem>> getCountries() async {
    final rows =
        await (_db.select(_db.countries)
              ..where((t) => t.isActive.equals(true))
              ..orderBy([
                (t) => OrderingTerm(expression: t.sortOrder),
                (t) => OrderingTerm(expression: t.key),
              ]))
            .get();
    // `sort_order` reflects English-alphabetical seeding order; dropdowns
    // display `nameAr`, so re-sort here for Arabic readers. Palestine stays
    // pinned first regardless of alphabetical position.
    rows.sort((a, b) {
      if (a.key == 'ps') return -1;
      if (b.key == 'ps') return 1;
      return a.nameAr.compareTo(b.nameAr);
    });
    return rows
        .map(
          (r) => ReferenceItem(
            key: r.key,
            nameAr: r.nameAr,
            nameEn: r.nameEn,
            sortOrder: r.sortOrder,
          ),
        )
        .toList();
  }

  @override
  Future<ReferenceItem?> getCountryByKey(String key) async {
    final row =
        await (_db.select(_db.countries)
              ..where((t) => t.key.equals(key) & t.isActive.equals(true)))
            .getSingleOrNull();
    if (row == null) return null;
    return ReferenceItem(
      key: row.key,
      nameAr: row.nameAr,
      nameEn: row.nameEn,
      sortOrder: row.sortOrder,
    );
  }

  @override
  Future<List<ReferenceItem>> getTrustLevels() async {
    final rows =
        await (_db.select(_db.trustLevels)
              ..where((t) => t.isActive.equals(true))
              ..orderBy([
                (t) => OrderingTerm(expression: t.sortOrder),
                (t) => OrderingTerm(expression: t.key),
              ]))
            .get();
    return rows
        .map(
          (r) => ReferenceItem(
            key: r.key,
            nameAr: r.nameAr,
            nameEn: r.nameEn,
            sortOrder: r.sortOrder,
          ),
        )
        .toList();
  }

  @override
  Future<List<ReferenceItem>> getUsageRights() async {
    final rows =
        await (_db.select(_db.usageRights)
              ..where((t) => t.isActive.equals(true))
              ..orderBy([
                (t) => OrderingTerm(expression: t.sortOrder),
                (t) => OrderingTerm(expression: t.key),
              ]))
            .get();
    return rows
        .map(
          (r) => ReferenceItem(
            key: r.key,
            nameAr: r.nameAr,
            nameEn: r.nameEn,
            sortOrder: r.sortOrder,
          ),
        )
        .toList();
  }

  @override
  Future<List<ReferenceItem>> getMetadataQualities() async {
    final rows =
        await (_db.select(_db.metadataQualities)
              ..where((t) => t.isActive.equals(true))
              ..orderBy([
                (t) => OrderingTerm(expression: t.sortOrder),
                (t) => OrderingTerm(expression: t.key),
              ]))
            .get();
    return rows
        .map(
          (r) => ReferenceItem(
            key: r.key,
            nameAr: r.nameAr,
            nameEn: r.nameEn,
            sortOrder: r.sortOrder,
          ),
        )
        .toList();
  }

  @override
  Future<List<ReferenceItem>> getWorkflowStatuses() async {
    final rows =
        await (_db.select(_db.workflowStatuses)
              ..where((t) => t.isActive.equals(true))
              ..orderBy([
                (t) => OrderingTerm(expression: t.sortOrder),
                (t) => OrderingTerm(expression: t.key),
              ]))
            .get();
    return rows
        .map(
          (r) => ReferenceItem(
            key: r.key,
            nameAr: r.nameAr,
            nameEn: r.nameEn,
            sortOrder: r.sortOrder,
          ),
        )
        .toList();
  }

  @override
  Future<List<ReferenceItem>> getFileRoles() async {
    final rows =
        await (_db.select(_db.fileRoles)
              ..where((t) => t.isActive.equals(true))
              ..orderBy([
                (t) => OrderingTerm(expression: t.sortOrder),
                (t) => OrderingTerm(expression: t.key),
              ]))
            .get();
    return rows
        .map(
          (r) => ReferenceItem(
            key: r.key,
            nameAr: r.nameAr,
            nameEn: r.nameEn,
            sortOrder: r.sortOrder,
          ),
        )
        .toList();
  }

  @override
  Future<List<ReferenceItem>> getFileHealthStatuses() async {
    final rows =
        await (_db.select(_db.fileHealthStatuses)
              ..where((t) => t.isActive.equals(true))
              ..orderBy([
                (t) => OrderingTerm(expression: t.sortOrder),
                (t) => OrderingTerm(expression: t.key),
              ]))
            .get();
    return rows
        .map(
          (r) => ReferenceItem(
            key: r.key,
            nameAr: r.nameAr,
            nameEn: r.nameEn,
            sortOrder: r.sortOrder,
          ),
        )
        .toList();
  }
}
