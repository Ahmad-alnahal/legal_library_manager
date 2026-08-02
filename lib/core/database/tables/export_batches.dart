// drift CHECK constraints reference the column getter, which the analyzer reads
// as a recursive getter even though drift_dev only resolves it statically.
// ignore_for_file: recursive_getters
import 'package:drift/drift.dart';

import '../../constants/domain_keys.dart';

/// Local export-batch records (spec §10.1).
///
/// `status_key` is constrained to the documented statuses (`uploaded` is
/// reserved for future use but schema-valid). Counts/sizes default to 0 and
/// reject negatives; `checksum_algorithm` defaults to `SHA-256`.
@DataClassName('ExportBatch')
@TableIndex(name: 'ix_export_batches_created_at', columns: {#createdAt})
class ExportBatches extends Table {
  @override
  String get tableName => 'export_batches';

  IntColumn get id => integer().autoIncrement()();
  TextColumn get batchCode => text().unique()();
  TextColumn get exportPath => text()();
  // CHECK status_key IN ('preparing','completed','failed','verified','uploaded').
  TextColumn get statusKey => text().check(
    statusKey.isIn(const [
      ExportBatchStatusKey.preparing,
      ExportBatchStatusKey.completed,
      ExportBatchStatusKey.failed,
      ExportBatchStatusKey.verified,
      ExportBatchStatusKey.uploaded,
    ]),
  )();
  IntColumn get documentCount => integer()
      .withDefault(const Constant(0))
      .check(documentCount.isBiggerOrEqualValue(0))();
  IntColumn get totalSizeBytes => integer()
      .withDefault(const Constant(0))
      .check(totalSizeBytes.isBiggerOrEqualValue(0))();
  TextColumn get checksumAlgorithm =>
      text().withDefault(const Constant('SHA-256'))();
  TextColumn get createdAt => text()();
  TextColumn get completedAt => text().nullable()();
}
