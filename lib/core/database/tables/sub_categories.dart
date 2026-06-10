import 'package:drift/drift.dart';

import 'main_categories.dart';

/// Legal subcategories reference table (spec §5.5).
///
/// [mainCategoryId] references [MainCategories.id] so a subcategory always
/// belongs to a valid main category (enforced when foreign keys are on).
///
/// [normalizedNameAr] / [normalizedNameEn] are internal, never-displayed
/// comparison values produced by the shared category-name normalization. They
/// back the per-parent composite unique indexes that enforce duplicate-name
/// integrity within one main category and are always written together with the
/// display names.
class SubCategories extends Table {
  @override
  String get tableName => 'sub_categories';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get mainCategoryId => integer().references(MainCategories, #id)();
  TextColumn get key => text().unique()();
  TextColumn get nameAr => text()();
  TextColumn get nameEn => text()();
  TextColumn get normalizedNameAr => text()();
  TextColumn get normalizedNameEn => text()();
  IntColumn get sortOrder => integer()();
  BoolColumn get isActive => boolean()();
}
