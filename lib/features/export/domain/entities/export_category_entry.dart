// lib/features/export/domain/entities/export_category_entry.dart

import 'package:equatable/equatable.dart';

/// Website-safe subcategory entry nested under an [ExportCategoryEntry].
class ExportSubcategoryEntry extends Equatable {
  const ExportSubcategoryEntry({
    required this.subcategoryKey,
    required this.subcategoryNameAr,
    required this.subcategoryNameEn,
    required this.sortOrder,
  });

  final String subcategoryKey;
  final String subcategoryNameAr;
  final String subcategoryNameEn;
  final int sortOrder;

  @override
  List<Object?> get props => [
    subcategoryKey,
    subcategoryNameAr,
    subcategoryNameEn,
    sortOrder,
  ];
}

/// Website-safe active main category with its active subcategories.
class ExportCategoryEntry extends Equatable {
  const ExportCategoryEntry({
    required this.mainCategoryKey,
    required this.mainCategoryNameAr,
    required this.mainCategoryNameEn,
    required this.sortOrder,
    required this.subcategories,
  });

  final String mainCategoryKey;
  final String mainCategoryNameAr;
  final String mainCategoryNameEn;
  final int sortOrder;
  final List<ExportSubcategoryEntry> subcategories;

  @override
  List<Object?> get props => [
    mainCategoryKey,
    mainCategoryNameAr,
    mainCategoryNameEn,
    sortOrder,
    subcategories,
  ];
}
