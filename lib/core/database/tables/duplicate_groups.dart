// drift CHECK constraints reference the column getter, which the analyzer reads
// as a recursive getter even though drift_dev only resolves it statically.
// ignore_for_file: recursive_getters
import 'package:drift/drift.dart';

import 'document_files.dart';

/// A group of exact-duplicate physical files sharing one SHA-256 (spec §7.1).
///
/// `preferred_file_id` references a `document_files` row with `ON DELETE
/// RESTRICT`. Whether the preferred file actually belongs to the group is
/// enforced later by transactional repository validation, not at the DB level.
@TableIndex(
  name: 'ux_duplicate_groups_sha256_hash',
  columns: {#sha256Hash},
  unique: true,
)
class DuplicateGroups extends Table {
  @override
  String get tableName => 'duplicate_groups';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get groupCode => text().unique()();
  TextColumn get sha256Hash => text()();
  IntColumn get preferredFileId => integer().nullable().references(
    DocumentFiles,
    #id,
    onDelete: KeyAction.restrict,
  )();
  // CHECK (review_status_key IN ('unreviewed','reviewed','archived_for_later')).
  TextColumn get reviewStatusKey => text()
      .check(
        reviewStatusKey.isIn(const [
          'unreviewed',
          'reviewed',
          'archived_for_later',
        ]),
      )
      .withDefault(const Constant('unreviewed'))();
  TextColumn get notes => text().nullable()();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();
}
