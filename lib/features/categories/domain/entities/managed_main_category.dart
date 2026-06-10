// lib/features/categories/domain/entities/managed_main_category.dart

import 'package:equatable/equatable.dart';

/// A main legal category as seen by the management workspace.
///
/// Unlike the read-only reference entity, this includes inactive categories and
/// exposes [isActive] so the workspace can show and toggle status. The stable
/// internal [key] and database [id] never change after creation.
class ManagedMainCategory extends Equatable {
  const ManagedMainCategory({
    required this.id,
    required this.key,
    required this.nameAr,
    required this.nameEn,
    required this.sortOrder,
    required this.isActive,
  });

  final int id;
  final String key;
  final String nameAr;
  final String nameEn;
  final int sortOrder;
  final bool isActive;

  @override
  List<Object?> get props => [id, key, nameAr, nameEn, sortOrder, isActive];
}
