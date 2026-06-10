// lib/features/categories/domain/entities/managed_sub_category.dart

import 'package:equatable/equatable.dart';

/// A legal subcategory as seen by the management workspace, always bound to a
/// parent main category. Includes inactive rows and exposes [isActive]. The
/// stable internal [key] and database [id] never change after creation.
class ManagedSubCategory extends Equatable {
  const ManagedSubCategory({
    required this.id,
    required this.mainCategoryId,
    required this.key,
    required this.nameAr,
    required this.nameEn,
    required this.sortOrder,
    required this.isActive,
  });

  final int id;
  final int mainCategoryId;
  final String key;
  final String nameAr;
  final String nameEn;
  final int sortOrder;
  final bool isActive;

  @override
  List<Object?> get props => [
    id,
    mainCategoryId,
    key,
    nameAr,
    nameEn,
    sortOrder,
    isActive,
  ];
}
