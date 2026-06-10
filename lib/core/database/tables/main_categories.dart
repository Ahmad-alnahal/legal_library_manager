import 'package:drift/drift.dart';

/// Main legal categories reference table (spec §5.4).
///
/// [normalizedNameAr] / [normalizedNameEn] are internal, never-displayed
/// comparison values produced by the shared category-name normalization. They
/// back the global unique indexes that enforce duplicate-name integrity and are
/// always written together with the display names.
class MainCategories extends Table {
  @override
  String get tableName => 'main_categories';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get key => text().unique()();
  TextColumn get nameAr => text()();
  TextColumn get nameEn => text()();
  TextColumn get normalizedNameAr => text()();
  TextColumn get normalizedNameEn => text()();
  IntColumn get sortOrder => integer()();
  BoolColumn get isActive => boolean()();
}
