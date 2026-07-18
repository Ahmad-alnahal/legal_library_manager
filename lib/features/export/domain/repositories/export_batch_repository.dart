// lib/features/export/domain/repositories/export_batch_repository.dart

import '../entities/export_batch_document_entry.dart';
import '../entities/export_batch_summary.dart';

/// Persistence boundary for export-batch records (`export_batches` and
/// `export_batch_documents`).
abstract class ExportBatchRepository {
  /// Allocates the next batch code in format `EXP-YYYY-MM-DD-NNN` (NNN =
  /// zero-padded 3 digits, derived from the MAX existing code numeric suffix
  /// for the given date — never from row count).
  Future<String> allocateBatchCode(DateTime now);

  /// Inserts a new `export_batches` row with `statusKey = 'preparing'`.
  /// Returns the new row id.
  Future<int> createBatch({
    required String batchCode,
    required String exportPath,
    required DateTime createdAt,
  });

  /// Inserts `export_batch_documents` rows for each entry.
  Future<void> insertBatchDocuments(List<ExportBatchDocumentEntry> entries);

  /// Updates the batch status to `verified` or `failed` and fills
  /// documentCount, totalSizeBytes, completedAt.
  Future<void> finalizeBatch({
    required int batchId,
    required String statusKey,
    required int documentCount,
    required int totalSizeBytes,
    required DateTime completedAt,
  });

  /// Lists all batches ordered by createdAt descending.
  Future<List<ExportBatchSummary>> listBatches();
}
