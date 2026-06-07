// lib/features/reference/domain/entities/sub_category_ref.dart

import 'package:equatable/equatable.dart';

/// A legal subcategory reference entry, always bound to a parent main category.
class SubCategoryRef extends Equatable {
  const SubCategoryRef({
    required this.id,
    required this.mainCategoryId,
    required this.key,
    required this.nameAr,
    required this.nameEn,
    required this.sortOrder,
  });

  final int id;
  final int mainCategoryId;
  final String key;
  final String nameAr;
  final String nameEn;
  final int sortOrder;

  @override
  List<Object?> get props => [
    id,
    mainCategoryId,
    key,
    nameAr,
    nameEn,
    sortOrder,
  ];
}
