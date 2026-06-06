// drift CHECK constraints reference the column getter, which the analyzer reads
// as a recursive getter even though drift_dev only resolves it statically.
// ignore_for_file: recursive_getters
import 'package:drift/drift.dart';

import 'documents.dart';
import 'reference_tables.dart';

/// Physical file occurrences and derivatives for a document (spec §5.2).
///
/// `document_id`, `file_role_key`, and `file_health_key` are foreign keys with
/// `ON DELETE RESTRICT` (spec §13). `absolute_path` is unique to prevent
/// importing the same physical path twice, `file_size_bytes` is non-negative,
/// and `file_health_key` defaults to `unknown`.
@TableIndex(
  name: 'ux_document_files_absolute_path',
  columns: {#absolutePath},
  unique: true,
)
@TableIndex(name: 'ix_document_files_document_id', columns: {#documentId})
@TableIndex(name: 'ix_document_files_sha256_hash', columns: {#sha256Hash})
@TableIndex(name: 'ix_document_files_file_role_key', columns: {#fileRoleKey})
@TableIndex(
  name: 'ix_document_files_file_health_key',
  columns: {#fileHealthKey},
)
@TableIndex(name: 'ix_document_files_extension', columns: {#extension})
class DocumentFiles extends Table {
  @override
  String get tableName => 'document_files';

  IntColumn get id => integer().autoIncrement()();
  IntColumn get documentId =>
      integer().references(Documents, #id, onDelete: KeyAction.restrict)();
  TextColumn get fileRoleKey =>
      text().references(FileRoles, #key, onDelete: KeyAction.restrict)();
  TextColumn get fileName => text()();
  TextColumn get absolutePath => text()();
  TextColumn get extension => text()();
  TextColumn get mimeType => text().nullable()();
  // CHECK (file_size_bytes >= 0). drift_dev resolves the column reference
  // statically to build the SQL; the getter is never executed at runtime.
  IntColumn get fileSizeBytes =>
      integer().check(fileSizeBytes.isBiggerOrEqualValue(0))();
  TextColumn get sha256Hash => text().nullable()();
  IntColumn get pageCount => integer().nullable()();
  TextColumn get fileHealthKey => text()
      .references(FileHealthStatuses, #key, onDelete: KeyAction.restrict)
      .withDefault(const Constant('unknown'))();
  BoolColumn get isReadOnlySource =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get isPreferred => boolean().withDefault(const Constant(false))();
  BoolColumn get existsLastChecked => boolean().nullable()();
  TextColumn get lastCheckedAt => text().nullable()();
  TextColumn get importedAt => text().nullable()();
  TextColumn get createdAt => text()();
  TextColumn get updatedAt => text()();
}
