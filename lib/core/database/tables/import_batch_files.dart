import 'package:drift/drift.dart';

import 'document_files.dart';
import 'import_batches.dart';

/// Per-file result rows for an import batch (spec §9.4).
///
/// Composite primary key `(import_batch_id, file_id)`. Deleting a batch cascades
/// its rows; a referenced file cannot be deleted (`ON DELETE RESTRICT`).
/// `result_key` has no CHECK because the finalized keys are not enumerated.
class ImportBatchFiles extends Table {
  @override
  String get tableName => 'import_batch_files';

  IntColumn get importBatchId =>
      integer().references(ImportBatches, #id, onDelete: KeyAction.cascade)();
  IntColumn get fileId =>
      integer().references(DocumentFiles, #id, onDelete: KeyAction.restrict)();
  TextColumn get resultKey => text()();
  TextColumn get createdAt => text()();

  @override
  Set<Column<Object>> get primaryKey => {importBatchId, fileId};
}
