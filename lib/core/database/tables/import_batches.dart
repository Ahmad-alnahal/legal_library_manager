// drift CHECK constraints reference the column getter, which the analyzer reads
// as a recursive getter even though drift_dev only resolves it statically.
// ignore_for_file: recursive_getters
import 'package:drift/drift.dart';

/// Import-scan batch records (spec §9.3).
///
/// `status_key` has no CHECK because the finalized import-batch status keys are
/// not enumerated in the schema spec. Count fields default to 0 and reject
/// negative values.
@DataClassName('ImportBatch')
@TableIndex(name: 'ix_import_batches_started_at', columns: {#startedAt})
class ImportBatches extends Table {
  @override
  String get tableName => 'import_batches';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get batchCode => text().unique()();
  TextColumn get sourceFolder => text()();
  BoolColumn get recursiveScan => boolean()();
  TextColumn get statusKey => text()();
  IntColumn get discoveredCount => integer()
      .withDefault(const Constant(0))
      .check(discoveredCount.isBiggerOrEqualValue(0))();
  IntColumn get importedCount => integer()
      .withDefault(const Constant(0))
      .check(importedCount.isBiggerOrEqualValue(0))();
  IntColumn get duplicateCount => integer()
      .withDefault(const Constant(0))
      .check(duplicateCount.isBiggerOrEqualValue(0))();
  IntColumn get failedCount => integer()
      .withDefault(const Constant(0))
      .check(failedCount.isBiggerOrEqualValue(0))();
  TextColumn get startedAt => text()();
  TextColumn get completedAt => text().nullable()();
}
