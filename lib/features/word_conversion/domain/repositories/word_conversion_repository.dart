// lib/features/word_conversion/domain/repositories/word_conversion_repository.dart

import '../entities/conversion_execution_record.dart';
import '../entities/conversion_review_item.dart';
import '../entities/conversion_work_item.dart';
import '../entities/word_conversion_record.dart';
import '../entities/word_source_record.dart';

/// Persistence boundary for the Word-to-PDF conversion workflow.
///
/// Implementations live in the data layer and may import Drift. Domain and
/// application layers depend only on this abstraction. Source file records
/// (`document_files` rows) are never mutated or deleted through any method
/// on this interface.
abstract class WordConversionRepository {
  /// Loads the `managed_library_root` setting.
  ///
  /// Returns null when the root is not yet configured.
  Future<String?> loadManagedLibraryRoot();

  /// Loads the [WordSourceRecord] for the `document_files` row with [fileId].
  ///
  /// Returns null when no row with that ID exists.
  Future<WordSourceRecord?> loadSourceRecord(int fileId);

  /// Returns an existing non-failed conversion row for [sourceFileId], or
  /// null when none exists.
  ///
  /// A `conversion_failed` row is ignored so that a re-staging attempt is
  /// allowed after a previous failure.
  Future<WordConversionRecord?> findActiveConversion(int sourceFileId);

  /// Transactionally inserts a `file_conversions` row with
  /// `status_key = pending_conversion` and appends a `conversion_started`
  /// `file_events` row.
  ///
  /// Returns the ID of the new `file_conversions` row.
  Future<int> persistConversionRecord({
    required int documentId,
    required int sourceFileId,
    required String converterKey,
    required String operationId,
    required String nowIso,
  });

  // ── P1.3 execution methods ────────────────────────────────────────────────

  /// Loads the full conversion row for execution by ID.
  ///
  /// Returns null when no row exists for [conversionId].
  Future<ConversionExecutionRecord?> loadConversionForExecution(
    int conversionId,
  );

  /// Atomically updates the status from `pending_conversion` to `converting`
  /// and records [nowIso] as `started_at`.
  ///
  /// Returns true when the update touched a row (the status was still
  /// `pending_conversion`). Returns false when the row was not found or the
  /// status had already changed.
  Future<bool> markConverting(int conversionId, String nowIso);

  /// Transactionally finalizes a successful conversion:
  ///   1. Inserts a `converted_pdf` `document_files` row.
  ///   2. Updates `file_conversions` to `needs_conversion_review` and records
  ///      `output_file_id` and `completed_at`.
  ///   3. Appends a `conversion_completed` `file_events` row.
  ///
  /// Returns the ID of the newly inserted `document_files` row.
  Future<int> finalizeSuccessfulConversion({
    required int conversionId,
    required int documentId,
    required int sourceFileId,
    required String outputPath,
    required String outputFileName,
    required String pdfSha256,
    required int fileSizeBytes,
    required String operationId,
    required String nowIso,
  });

  /// Transactionally records a conversion failure:
  ///   1. Updates `file_conversions` to `conversion_failed` with
  ///      `error_code`, `error_message_safe`, and `completed_at`.
  ///   2. Appends a `conversion_failed` `file_events` row.
  ///
  /// The source `document_files` row is never touched.
  Future<void> recordFailedConversion({
    required int conversionId,
    required int documentId,
    required int sourceFileId,
    required String errorCode,
    required String errorMessageSafe,
    required String operationId,
    required String nowIso,
  });

  // ── P1.4 review methods ───────────────────────────────────────────────────

  /// Returns all `file_conversions` rows with `status_key =
  /// needs_conversion_review`, joined with source and output `document_files`
  /// metadata, ordered newest first.
  Future<List<ConversionReviewItem>> loadPendingConversionReviews();

  /// Atomically approves a conversion quality review:
  ///   - Updates `file_conversions` status to `conversion_approved`,
  ///     sets `quality_approved = true`, `quality_reviewed_at = nowIso`.
  ///   - Only touches the row when its current status is
  ///     `needs_conversion_review`.
  ///
  /// Returns true when the update succeeded (the row was in the correct state).
  Future<bool> approveConversionReview({
    required int conversionId,
    required String nowIso,
  });

  /// Atomically rejects a conversion quality review:
  ///   - Updates `file_conversions` status to `conversion_failed`,
  ///     sets `quality_approved = false`, `quality_reviewed_at = nowIso`,
  ///     `error_code = review_rejected`, and `error_message_safe` to
  ///     [reviewNote] when provided.
  ///   - Only touches the row when its current status is
  ///     `needs_conversion_review`.
  ///
  /// Returns true when the update succeeded. Neither source nor output files
  /// are deleted or modified.
  Future<bool> rejectConversionReview({
    required int conversionId,
    required String nowIso,
    String? reviewNote,
  });

  // P1.5 operator-visible conversion work queue.

  /// Returns conversion rows that still need conversion work or attention:
  /// `pending_conversion`, `converting`, and `conversion_failed`.
  ///
  /// Rows already awaiting quality review or approved are excluded.
  Future<List<ConversionWorkItem>> loadConversionWorkQueue();

  /// Transactionally assigns a `DOC-xxxxxxx` code to [documentId] if none
  /// exists yet, then returns the (new or existing) code.
  ///
  /// Throws [StateError] when no more sequential codes are available (unlikely
  /// in practice: 9 999 999 slots). Throws on database error.
  Future<String> allocateDocumentCode(int documentId);
}
