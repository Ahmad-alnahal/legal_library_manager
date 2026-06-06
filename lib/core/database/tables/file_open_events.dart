// drift CHECK constraints reference the column getter, which the analyzer reads
// as a recursive getter even though drift_dev only resolves it statically.
// ignore_for_file: recursive_getters
import 'package:drift/drift.dart';

import 'document_files.dart';
import 'documents.dart';

/// Safe open-file / open-folder attempts (spec §9.2).
///
/// Kept separate from file mutation events. Policy: never log document contents
/// or arbitrary command strings (application-layer responsibility).
@TableIndex(
  name: 'ix_file_open_events_file_created',
  columns: {#fileId, #createdAt},
)
class FileOpenEvents extends Table {
  @override
  String get tableName => 'file_open_events';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get documentId => integer().nullable().references(
    Documents,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get fileId =>
      integer().references(DocumentFiles, #id, onDelete: KeyAction.restrict)();
  // CHECK (open_target_key IN ('file','folder')).
  TextColumn get openTargetKey =>
      text().check(openTargetKey.isIn(const ['file', 'folder']))();
  // CHECK (result_key IN ('succeeded','failed','blocked')).
  TextColumn get resultKey =>
      text().check(resultKey.isIn(const ['succeeded', 'failed', 'blocked']))();
  TextColumn get errorCode => text().nullable()();
  TextColumn get messageSafe => text().nullable()();
  TextColumn get createdAt => text()();
}
