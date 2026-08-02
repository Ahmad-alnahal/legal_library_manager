// lib/features/export/data/repositories/drift_export_batch_repository.dart

import 'package:drift/drift.dart';

import '../../../../core/constants/domain_keys.dart';
import '../../../../core/database/app_database.dart';
import '../../domain/entities/export_batch_document_entry.dart';
import '../../domain/entities/export_batch_summary.dart';
import '../../domain/repositories/export_batch_repository.dart';

/// Drift-backed [ExportBatchRepository].
class DriftExportBatchRepository implements ExportBatchRepository {
  const DriftExportBatchRepository(this._db);

  final AppDatabase _db;

  @override
  Future<String> allocateBatchCode(DateTime now) async {
    final String datePart = _formatDate(now);
    final String prefix = 'EXP-$datePart-';

    final List<TypedResult> rows =
        await (_db.selectOnly(_db.exportBatches)
              ..addColumns([_db.exportBatches.batchCode])
              ..where(_db.exportBatches.batchCode.like('$prefix%')))
            .get();

    final RegExp suffixPattern = RegExp('^${RegExp.escape(prefix)}(\\d{3})\$');
    int maxNum = 0;
    for (final TypedResult row in rows) {
      final String? code = row.read(_db.exportBatches.batchCode);
      if (code == null) continue;
      final RegExpMatch? match = suffixPattern.firstMatch(code);
      if (match != null) {
        final int n = int.tryParse(match.group(1)!) ?? 0;
        if (n > maxNum) maxNum = n;
      }
    }

    final int next = maxNum + 1;
    return '$prefix${next.toString().padLeft(3, '0')}';
  }

  @override
  Future<int> createBatch({
    required String batchCode,
    required String exportPath,
    required DateTime createdAt,
  }) {
    return _db
        .into(_db.exportBatches)
        .insert(
          ExportBatchesCompanion.insert(
            batchCode: batchCode,
            exportPath: exportPath,
            statusKey: ExportBatchStatusKey.preparing,
            createdAt: createdAt.toIso8601String(),
          ),
        );
  }

  @override
  Future<void> insertBatchDocuments(
    List<ExportBatchDocumentEntry> entries,
  ) async {
    for (final ExportBatchDocumentEntry entry in entries) {
      await _db
          .into(_db.exportBatchDocuments)
          .insert(
            ExportBatchDocumentsCompanion.insert(
              exportBatchId: entry.batchId,
              documentId: entry.documentId,
              managedFileId: entry.managedFileId,
              sha256Hash: entry.sha256Hash,
              createdAt: entry.createdAt.toIso8601String(),
            ),
          );
    }
  }

  @override
  Future<void> finalizeBatch({
    required int batchId,
    required String statusKey,
    required int documentCount,
    required int totalSizeBytes,
    required DateTime completedAt,
  }) async {
    await (_db.update(
      _db.exportBatches,
    )..where((b) => b.id.equals(batchId))).write(
      ExportBatchesCompanion(
        statusKey: Value(statusKey),
        documentCount: Value(documentCount),
        totalSizeBytes: Value(totalSizeBytes),
        completedAt: Value(completedAt.toIso8601String()),
      ),
    );
  }

  @override
  Future<List<ExportBatchSummary>> listBatches() async {
    final List<ExportBatch> rows = await (_db.select(
      _db.exportBatches,
    )..orderBy([(b) => OrderingTerm.desc(b.createdAt)])).get();
    return rows
        .map(
          (row) => ExportBatchSummary(
            id: row.id,
            batchCode: row.batchCode,
            exportPath: row.exportPath,
            statusKey: row.statusKey,
            documentCount: row.documentCount,
            totalSizeBytes: row.totalSizeBytes,
            createdAt: DateTime.parse(row.createdAt),
            completedAt: row.completedAt == null
                ? null
                : DateTime.parse(row.completedAt!),
          ),
        )
        .toList(growable: false);
  }

  String _formatDate(DateTime d) {
    final String y = d.year.toString().padLeft(4, '0');
    final String m = d.month.toString().padLeft(2, '0');
    final String day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }
}
