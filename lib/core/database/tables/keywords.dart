import 'package:drift/drift.dart';

import 'reference_tables.dart';

/// Normalized keyword vocabulary (spec §5.7).
///
/// `normalized_value` is unique (used for matching); `language_key` is an
/// optional reference with `ON DELETE RESTRICT`.
@TableIndex(
  name: 'ux_keywords_normalized_value',
  columns: {#normalizedValue},
  unique: true,
)
class Keywords extends Table {
  @override
  String get tableName => 'keywords';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get normalizedValue => text()();
  TextColumn get displayValue => text()();
  TextColumn get languageKey => text().nullable().references(
    Languages,
    #key,
    onDelete: KeyAction.restrict,
  )();
  TextColumn get createdAt => text()();
}
