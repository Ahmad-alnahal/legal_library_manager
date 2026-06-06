import 'package:drift/drift.dart';

import 'document_files.dart';
import 'documents.dart';
import 'export_batches.dart';

/// Document snapshots included in an export batch (spec §10.2).
///
/// Composite primary key `(export_batch_id, document_id)`. Deleting a batch
/// cascades its snapshot rows; the referenced document and managed file cannot
/// be deleted while referenced (`ON DELETE RESTRICT`). `sha256_hash` is a
/// required integrity snapshot.
class ExportBatchDocuments extends Table {
  @override
  String get tableName => 'export_batch_documents';

  IntColumn get exportBatchId =>
      integer().references(ExportBatches, #id, onDelete: KeyAction.cascade)();
  IntColumn get documentId =>
      integer().references(Documents, #id, onDelete: KeyAction.restrict)();
  IntColumn get managedFileId =>
      integer().references(DocumentFiles, #id, onDelete: KeyAction.restrict)();
  TextColumn get sha256Hash => text()();
  TextColumn get createdAt => text()();

  @override
  Set<Column<Object>> get primaryKey => {exportBatchId, documentId};
}
