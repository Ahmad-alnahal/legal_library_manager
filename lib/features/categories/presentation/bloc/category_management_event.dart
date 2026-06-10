// lib/features/categories/presentation/bloc/category_management_event.dart

import 'package:equatable/equatable.dart';

sealed class CategoryManagementEvent extends Equatable {
  const CategoryManagementEvent();

  @override
  List<Object?> get props => [];
}

/// Initial load of all main categories and subcategories.
class CategoryManagementStarted extends CategoryManagementEvent {
  const CategoryManagementStarted();
}

/// Retry the last failed load.
class CategoryManagementRetryRequested extends CategoryManagementEvent {
  const CategoryManagementRetryRequested();
}

/// Select which main category's subcategories are shown (null = none).
class CategoryMainSelected extends CategoryManagementEvent {
  const CategoryMainSelected(this.mainCategoryId);

  final int? mainCategoryId;

  @override
  List<Object?> get props => [mainCategoryId];
}

/// Toggle whether inactive categories are listed.
class CategoryShowInactiveToggled extends CategoryManagementEvent {
  const CategoryShowInactiveToggled(this.showInactive);

  final bool showInactive;

  @override
  List<Object?> get props => [showInactive];
}

class MainCategoryCreateRequested extends CategoryManagementEvent {
  const MainCategoryCreateRequested({
    required this.nameAr,
    required this.nameEn,
  });

  final String nameAr;
  final String nameEn;

  @override
  List<Object?> get props => [nameAr, nameEn];
}

class MainCategoryUpdateRequested extends CategoryManagementEvent {
  const MainCategoryUpdateRequested({
    required this.id,
    required this.nameAr,
    required this.nameEn,
  });

  final int id;
  final String nameAr;
  final String nameEn;

  @override
  List<Object?> get props => [id, nameAr, nameEn];
}

class MainCategoryActiveSet extends CategoryManagementEvent {
  const MainCategoryActiveSet({required this.id, required this.isActive});

  final int id;
  final bool isActive;

  @override
  List<Object?> get props => [id, isActive];
}

/// Swaps the positions of [idA] and [idB] in the main-category list and
/// resequences all main categories.
class MainCategoryReorderRequested extends CategoryManagementEvent {
  const MainCategoryReorderRequested({required this.idA, required this.idB});

  final int idA;
  final int idB;

  @override
  List<Object?> get props => [idA, idB];
}

class SubCategoryCreateRequested extends CategoryManagementEvent {
  const SubCategoryCreateRequested({
    required this.mainCategoryId,
    required this.nameAr,
    required this.nameEn,
  });

  final int mainCategoryId;
  final String nameAr;
  final String nameEn;

  @override
  List<Object?> get props => [mainCategoryId, nameAr, nameEn];
}

class SubCategoryUpdateRequested extends CategoryManagementEvent {
  const SubCategoryUpdateRequested({
    required this.id,
    required this.nameAr,
    required this.nameEn,
  });

  final int id;
  final String nameAr;
  final String nameEn;

  @override
  List<Object?> get props => [id, nameAr, nameEn];
}

class SubCategoryActiveSet extends CategoryManagementEvent {
  const SubCategoryActiveSet({required this.id, required this.isActive});

  final int id;
  final bool isActive;

  @override
  List<Object?> get props => [id, isActive];
}

/// Swaps the positions of [idA] and [idB] within their shared parent and
/// resequences that sibling collection.
class SubCategoryReorderRequested extends CategoryManagementEvent {
  const SubCategoryReorderRequested({required this.idA, required this.idB});

  final int idA;
  final int idB;

  @override
  List<Object?> get props => [idA, idB];
}

class SubCategoryMoveRequested extends CategoryManagementEvent {
  const SubCategoryMoveRequested({
    required this.subCategoryId,
    required this.newMainCategoryId,
  });

  final int subCategoryId;
  final int newMainCategoryId;

  @override
  List<Object?> get props => [subCategoryId, newMainCategoryId];
}
