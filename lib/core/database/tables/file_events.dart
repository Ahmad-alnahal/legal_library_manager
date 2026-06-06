// drift CHECK constraints reference the column getter, which the analyzer reads
// as a recursive getter even though drift_dev only resolves it statically.
// ignore_for_file: recursive_getters
import 'package:drift/drift.dart';

import 'document_files.dart';
import 'documents.dart';

/// Append-only file-operation audit history (spec §9.1).
///
/// Policy: this table must never store document contents or unsafe/arbitrary
/// shell command strings. Only safe paths, hashes, result/error codes, and
/// short safe messages are recorded; enforcement is an application-layer
/// responsibility, not a DB constraint.
@TableIndex(
  name: 'ix_file_events_document_created',
  columns: {#documentId, #createdAt},
)
@TableIndex(name: 'ix_file_events_file_created', columns: {#fileId, #createdAt})
@TableIndex(name: 'ix_file_events_operation_id', columns: {#operationId})
class FileEvents extends Table {
  @override
  String get tableName => 'file_events';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get documentId => integer().nullable().references(
    Documents,
    #id,
    onDelete: KeyAction.restrict,
  )();
  IntColumn get fileId => integer().nullable().references(
    DocumentFiles,
    #id,
    onDelete: KeyAction.restrict,
  )();
  // CHECK event_type_key IN (...the finalized §9.1 event keys...).
  TextColumn get eventTypeKey => text().check(
    eventTypeKey.isIn(const [
      'discovered',
      'hash_started',
      'hash_completed',
      'hash_failed',
      'imported',
      'copy_started',
      'copy_completed',
      'copy_verified',
      'copy_failed',
      'existence_checked',
      'marked_missing',
      'conversion_started',
      'conversion_completed',
      'conversion_failed',
      'backup_created',
      'export_copy_created',
    ]),
  )();
  TextColumn get operationId => text()();
  TextColumn get sourcePath => text().nullable()();
  TextColumn get destinationPath => text().nullable()();
  TextColumn get expectedSha256 => text().nullable()();
  TextColumn get actualSha256 => text().nullable()();
  // CHECK (result_key IN ('started','succeeded','failed','warning')).
  TextColumn get resultKey => text().check(
    resultKey.isIn(const ['started', 'succeeded', 'failed', 'warning']),
  )();
  TextColumn get errorCode => text().nullable()();
  TextColumn get messageSafe => text().nullable()();
  TextColumn get createdAt => text()();
}
