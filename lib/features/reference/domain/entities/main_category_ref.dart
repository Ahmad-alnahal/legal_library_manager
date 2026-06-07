// lib/features/reference/domain/entities/main_category_ref.dart

import 'package:equatable/equatable.dart';

/// A main legal category reference entry.
class MainCategoryRef extends Equatable {
  const MainCategoryRef({
    required this.id,
    required this.key,
    required this.nameAr,
    required this.nameEn,
    required this.sortOrder,
  });

  final int id;
  final String key;
  final String nameAr;
  final String nameEn;
  final int sortOrder;

  @override
  List<Object?> get props => [id, key, nameAr, nameEn, sortOrder];
}
