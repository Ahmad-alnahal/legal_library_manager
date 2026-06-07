// lib/features/reference/domain/repositories/reference_repository.dart

import '../entities/document_type_ref.dart';
import '../entities/main_category_ref.dart';
import '../entities/reference_item.dart';
import '../entities/sub_category_ref.dart';

/// Read-only, domain-facing contract for accessing seeded reference data.
///
/// All methods return only active rows by default, in a stable, deterministic
/// order (by `sort_order` then key/id). The contract exposes no mutation
/// methods — reference data is owned by the seeders. Implementations keep all
/// persistence-specific types inside the data layer.
abstract class ReferenceRepository {
  /// Active document types, ordered by sort order then key.
  Future<List<DocumentTypeRef>> getDocumentTypes();

  /// Active main legal categories, ordered by sort order then key.
  Future<List<MainCategoryRef>> getMainCategories();

  /// Active subcategories, ordered by sort order then key.
  ///
  /// Optionally filtered to a single parent main category by numeric
  /// [mainCategoryId] or by stable [mainCategoryKey]. At most one filter may be
  /// supplied. Filtering by an unknown key yields an empty list.
  Future<List<SubCategoryRef>> getSubCategories({
    int? mainCategoryId,
    String? mainCategoryKey,
  });

  /// Active document languages.
  Future<List<ReferenceItem>> getLanguages();

  /// Active countries, in canonical order (Palestine first, then by English
  /// display name).
  Future<List<ReferenceItem>> getCountries();

  /// The active country with the given key, or `null` if not found/inactive.
  Future<ReferenceItem?> getCountryByKey(String key);

  /// Active trust levels.
  Future<List<ReferenceItem>> getTrustLevels();

  /// Active usage-rights options.
  Future<List<ReferenceItem>> getUsageRights();

  /// Active metadata-quality levels.
  Future<List<ReferenceItem>> getMetadataQualities();

  /// Active workflow statuses.
  Future<List<ReferenceItem>> getWorkflowStatuses();

  /// Active file roles.
  Future<List<ReferenceItem>> getFileRoles();

  /// Active file-health statuses.
  Future<List<ReferenceItem>> getFileHealthStatuses();
}
