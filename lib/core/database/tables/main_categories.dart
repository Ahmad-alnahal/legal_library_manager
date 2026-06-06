import 'package:drift/drift.dart';

/// Main legal categories reference table (spec §5.4).
class MainCategories extends Table {
  @override
  String get tableName => 'main_categories';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get key => text().unique()();
  TextColumn get nameAr => text()();
  TextColumn get nameEn => text()();
  IntColumn get sortOrder => integer()();
  BoolColumn get isActive => boolean()();
}
