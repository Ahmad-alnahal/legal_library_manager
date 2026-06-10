// lib/features/categories/domain/repositories/category_management_repository.dart

import '../entities/managed_main_category.dart';
import '../entities/managed_sub_category.dart';

/// Persistence-agnostic contract for managing main categories and subcategories.
///
/// Implementations confine all persistence types to the data layer and run any
/// multi-step check-then-write as a single transaction. Mutations never delete
/// rows (categories are deactivated, never removed) and never touch source
/// files. Stable internal keys and database ids are immutable after creation.
/// Sort order is managed exclusively by the repository: callers never supply
/// or edit numeric sort positions.
abstract class CategoryManagementRepository {
  /// All main categories (active and inactive), ordered by sort order then key.
  Future<List<ManagedMainCategory>> getMainCategories();

  /// All subcategories (active and inactive), optionally filtered to one parent,
  /// ordered by sort order then key.
  Future<List<ManagedSubCategory>> getSubCategories({int? mainCategoryId});

  /// Inserts a new main category with an immutable [key], automatically placed
  /// last among all existing main categories. The insert and the
  /// normalized-name uniqueness check run in one transaction.
  ///
  /// Throws [DuplicateCategoryNameException] if a main category already uses the
  /// same normalized Arabic or English name, or [CategoryKeyCollisionException]
  /// if the generated key already exists.
  Future<int> insertMainCategory({
    required String key,
    required String nameAr,
    required String nameEn,
  });

  /// Inserts a new subcategory under [mainCategoryId] with an immutable [key],
  /// automatically placed last among its siblings.
  ///
  /// Throws [DuplicateCategoryNameException] if a subcategory under the same
  /// parent already uses the same normalized Arabic or English name, or
  /// [CategoryKeyCollisionException] on a key collision.
  Future<int> insertSubCategory({
    required int mainCategoryId,
    required String key,
    required String nameAr,
    required String nameEn,
  });

  /// Updates a main category's display names. The id, key, and sort order are
  /// never changed. Throws [DuplicateCategoryNameException] on a normalized-name
  /// collision with another main category.
  Future<void> updateMainCategory({
    required int id,
    required String nameAr,
    required String nameEn,
  });

  /// Updates a subcategory's display names within its current parent. The id,
  /// key, parent, and sort order are never changed here. Throws
  /// [DuplicateCategoryNameException] on a normalized-name collision under the
  /// same parent.
  Future<void> updateSubCategory({
    required int id,
    required String nameAr,
    required String nameEn,
  });

  /// Activates or deactivates a main category. Ids stay stable so existing
  /// documents keep referencing it.
  Future<void> setMainCategoryActive(int id, {required bool isActive});

  /// Activates or deactivates a subcategory.
  Future<void> setSubCategoryActive(int id, {required bool isActive});

  /// Moves an *unused* subcategory to another main category, placing it last
  /// among the target siblings, and resequences both the source and target
  /// sibling collections.
  ///
  /// Throws [SubCategoryInUseException] if the subcategory is referenced by any
  /// document, and [DuplicateCategoryNameException] if a subcategory with the
  /// same normalized name already exists under the target parent.
  Future<void> moveSubCategory({
    required int subCategoryId,
    required int newMainCategoryId,
  });

  /// Whether [subCategoryId] is referenced by any document — either as a
  /// document's primary subcategory or in any document-classification row.
  Future<bool> isSubCategoryUsed(int subCategoryId);

  /// Swaps the display positions of two main categories ([idA] and [idB]) and
  /// resequences the full main-category collection with sequential positions.
  /// Inactive categories are included in the resequencing but their relative
  /// positions are changed only if one of them is directly named.
  Future<void> reorderMainCategory({required int idA, required int idB});

  /// Swaps the display positions of two sibling subcategories and resequences
  /// all subcategories under their shared parent. [idA] and [idB] must belong
  /// to the same main category.
  Future<void> reorderSubCategory({required int idA, required int idB});
}

/// Thrown when a category write would create a duplicate normalized display
/// name. [field] is `nameAr` or `nameEn`.
class DuplicateCategoryNameException implements Exception {
  const DuplicateCategoryNameException(this.field);
  final String field;
  @override
  String toString() => 'DuplicateCategoryNameException($field)';
}

/// Thrown when a subcategory move is rejected because the subcategory is still
/// referenced by one or more documents.
class SubCategoryInUseException implements Exception {
  const SubCategoryInUseException();
  @override
  String toString() => 'SubCategoryInUseException';
}

/// Thrown when a generated immutable key collides with an existing one.
class CategoryKeyCollisionException implements Exception {
  const CategoryKeyCollisionException();
  @override
  String toString() => 'CategoryKeyCollisionException';
}

/// Thrown when a write targets an inactive main category.
class InactiveMainCategoryException implements Exception {
  const InactiveMainCategoryException();
  @override
  String toString() => 'InactiveMainCategoryException';
}
