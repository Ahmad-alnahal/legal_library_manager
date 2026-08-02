// lib/features/documents/domain/validation/membership_validators.dart

import '../../../../core/constants/domain_keys.dart';
import '../../../reference/domain/entities/sub_category_ref.dart';

/// Pure, reusable cross-table membership checks required by finalized schema
/// rules. These are independent of persistence (they take already-loaded data)
/// so they can back document, duplicate, and export workflows alike.
abstract final class MembershipValidators {
  /// True if [subCategory] belongs to the given [mainCategoryId].
  static bool subCategoryBelongsToMain(
    SubCategoryRef subCategory,
    int mainCategoryId,
  ) => subCategory.mainCategoryId == mainCategoryId;

  /// True if a subcategory id is a member of [mainCategoryId], given the set of
  /// `(subCategoryId -> mainCategoryId)` mappings for active subcategories.
  static bool subCategoryIdBelongsToMain({
    required int subCategoryId,
    required int mainCategoryId,
    required Map<int, int> mainBySubCategoryId,
  }) => mainBySubCategoryId[subCategoryId] == mainCategoryId;

  /// True if a duplicate group's [preferredFileId] is a member of the group.
  ///
  /// A null preferred file is allowed (no preference set).
  static bool preferredFileBelongsToGroup({
    required int? preferredFileId,
    required Set<int> groupFileIds,
  }) {
    if (preferredFileId == null) return true;
    return groupFileIds.contains(preferredFileId);
  }

  /// True if an export snapshot's managed file belongs to the snapshot document
  /// and is an actual managed copy (`file_role_key == 'managed_copy'`).
  static bool exportManagedFileIsValid({
    required int snapshotDocumentId,
    required int fileDocumentId,
    required String fileRoleKey,
  }) =>
      fileDocumentId == snapshotDocumentId &&
      fileRoleKey == FileRoleKey.managedCopy;
}
