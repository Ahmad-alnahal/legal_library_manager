import 'package:drift/drift.dart';

import 'document_files.dart';
import 'duplicate_groups.dart';

/// Membership of physical files in a duplicate group (spec §7.2).
///
/// Composite primary key `(duplicate_group_id, file_id)`. Deleting a group
/// cascades its membership rows; a member file cannot be deleted while still
/// referenced (`ON DELETE RESTRICT`). `file_id` is intentionally NOT unique —
/// the finalized spec allows a file to appear via the composite key only.
@TableIndex(name: 'ix_duplicate_group_members_file_id', columns: {#fileId})
class DuplicateGroupMembers extends Table {
  @override
  String get tableName => 'duplicate_group_members';

  IntColumn get duplicateGroupId =>
      integer().references(DuplicateGroups, #id, onDelete: KeyAction.cascade)();
  IntColumn get fileId =>
      integer().references(DocumentFiles, #id, onDelete: KeyAction.restrict)();
  BoolColumn get isHiddenFromSearch =>
      boolean().withDefault(const Constant(false))();
  TextColumn get addedAt => text()();

  @override
  Set<Column<Object>> get primaryKey => {duplicateGroupId, fileId};
}
