import 'package:drift/drift.dart';

/// Key/value application settings (spec §11.1).
///
/// Policy: the permanent copy-only source-file protection is NOT toggleable.
/// A settings row may record/display the policy, but no settings logic may be
/// allowed to disable it — enforcement belongs to later application logic, not
/// to this storage table.
class Settings extends Table {
  @override
  String get tableName => 'settings';

  TextColumn get key => text()();
  TextColumn get value => text()();
  TextColumn get updatedAt => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
