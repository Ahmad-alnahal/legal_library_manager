import 'package:drift/drift.dart';

import 'main_categories.dart';

/// Legal subcategories reference table (spec §5.5).
///
/// [mainCategoryId] references [MainCategories.id] so a subcategory always
/// belongs to a valid main category (enforced when foreign keys are on).
class SubCategories extends Table {
  @override
  String get tableName => 'sub_categories';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get mainCategoryId => integer().references(MainCategories, #id)();
  TextColumn get key => text().unique()();
  TextColumn get nameAr => text()();
  TextColumn get nameEn => text()();
  IntColumn get sortOrder => integer()();
  BoolColumn get isActive => boolean()();
}
