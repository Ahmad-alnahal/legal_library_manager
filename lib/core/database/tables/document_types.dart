import 'package:drift/drift.dart';

/// Document types reference table (spec §5.3).
///
/// Integer surrogate id with a unique English `snake_case` [key] and required
/// bilingual display names.
class DocumentTypes extends Table {
  @override
  String get tableName => 'document_types';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get key => text().unique()();
  TextColumn get nameAr => text()();
  TextColumn get nameEn => text()();
  IntColumn get sortOrder => integer()();
  BoolColumn get isActive => boolean()();
}
