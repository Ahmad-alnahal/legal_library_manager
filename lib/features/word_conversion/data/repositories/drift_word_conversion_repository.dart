// lib/features/word_conversion/data/repositories/drift_word_conversion_repository.dart

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/entities/conversion_execution_record.dart';
import '../../domain/entities/conversion_review_item.dart';
import '../../domain/entities/conversion_work_item.dart';
import '../../domain/entities/word_conversion_record.dart';
import '../../domain/entities/word_source_record.dart';
import '../../domain/repositories/word_conversion_repository.dart';

/// Drift-backed [WordConversionRepository].
///
/// Reads from [document_files] and [settings]; inserts into
/// [file_conversions] and [file_events]. Source file records are never
/// mutated or deleted by any method here.
class DriftWordConversionRepository implements WordConversionRepository {
  const DriftWordConversionRepository(this._db);

  final AppDatabase _db;

  static const String _managedLibraryKey = 'managed_library_root';
  static const String _pendingConversionStatus = 'pending_conversion';
  static const String _convertingStatus = 'converting';
  static const String _conversionFailedStatus = 'conversion_failed';
  static const String _needsReviewStatus = 'needs_conversion_review';
  static const String _conversionApprovedStatus = 'conversion_approved';
  static const String _reviewRejectedErrorCode = 'review_rejected';
  static const String _convertedPdfRole = 'converted_pdf';
  static const String _conversionStartedEvent = 'conversion_started';
  static const String _conversionCompletedEvent = 'conversion_completed';
  static const String _conversionFailedEvent = 'conversion_failed';
  static const String _startedResultKey = 'started';
  static const String _succeededResultKey = 'succeeded';
  static const String _failedResultKey = 'failed';

  // ── Settings ───────────────────────────────────────────────────────────────

  @override
  Future<String?> loadManagedLibraryRoot() async {
    final Setting? row = await (_db.select(
      _db.settings,
    )..where((s) => s.key.equals(_managedLibraryKey))).getSingleOrNull();
    final String? value = row?.value;
    if (value == null || value.trim().isEmpty) return null;
    return value;
  }

  // ── Source file lookup ─────────────────────────────────────────────────────

  @override
  Future<WordSourceRecord?> loadSourceRecord(int fileId) async {
    final DocumentFile? row = await (_db.select(
      _db.documentFiles,
    )..where((f) => f.id.equals(fileId))).getSingleOrNull();
    if (row == null) return null;
    return WordSourceRecord(
      fileId: row.id,
      documentId: row.documentId,
      absolutePath: row.absolutePath,
      extension: row.extension,
      sha256Hash: row.sha256Hash,
      fileHealthKey: row.fileHealthKey,
      fileRoleKey: row.fileRoleKey,
    );
  }

  // ── Conversion lookup ──────────────────────────────────────────────────────

  @override
  Future<WordConversionRecord?> findActiveConversion(int sourceFileId) async {
    final FileConversion? row =
        await (_db.select(_db.fileConversions)
              ..where(
                (c) =>
                    c.sourceFileId.equals(sourceFileId) &
                    c.statusKey.equals(_conversionFailedStatus).not(),
              )
              ..orderBy([(c) => OrderingTerm.desc(c.id)])
              ..limit(1))
            .getSingleOrNull();
    if (row == null) return null;
    return WordConversionRecord(conversionId: row.id, statusKey: row.statusKey);
  }

  // ── Persistence ────────────────────────────────────────────────────────────

  @override
  Future<int> persistConversionRecord({
    required int documentId,
    required int sourceFileId,
    required String converterKey,
    required String operationId,
    required String nowIso,
  }) {
    return _db.transaction(() async {
      final int conversionId = await _db
          .into(_db.fileConversions)
          .insert(
            FileConversionsCompanion.insert(
              documentId: documentId,
              sourceFileId: sourceFileId,
              statusKey: _pendingConversionStatus,
              converterKey: Value(converterKey),
              createdAt: nowIso,
              updatedAt: nowIso,
            ),
          );
      await _db
          .into(_db.fileEvents)
          .insert(
            FileEventsCompanion.insert(
              documentId: Value(documentId),
              fileId: Value(sourceFileId),
              eventTypeKey: _conversionStartedEvent,
              operationId: operationId,
              resultKey: _startedResultKey,
              createdAt: nowIso,
            ),
          );
      return conversionId;
    });
  }

  // ── P1.3 execution methods ─────────────────────────────────────────────────

  @override
  Future<ConversionExecutionRecord?> loadConversionForExecution(
    int conversionId,
  ) async {
    final FileConversion? row = await (_db.select(
      _db.fileConversions,
    )..where((c) => c.id.equals(conversionId))).getSingleOrNull();
    if (row == null) return null;
    return ConversionExecutionRecord(
      conversionId: row.id,
      documentId: row.documentId,
      sourceFileId: row.sourceFileId,
      statusKey: row.statusKey,
      converterKey: row.converterKey,
    );
  }

  @override
  Future<bool> markConverting(int conversionId, String nowIso) async {
    final rowsUpdated =
        await (_db.update(_db.fileConversions)..where(
              (c) =>
                  c.id.equals(conversionId) &
                  c.statusKey.equals(_pendingConversionStatus),
            ))
            .write(
              FileConversionsCompanion(
                statusKey: const Value(_convertingStatus),
                startedAt: Value(nowIso),
                updatedAt: Value(nowIso),
              ),
            );
    return rowsUpdated > 0;
  }

  @override
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
  }) {
    return _db.transaction(() async {
      final int outputFileId = await _db
          .into(_db.documentFiles)
          .insert(
            DocumentFilesCompanion.insert(
              documentId: documentId,
              fileRoleKey: _convertedPdfRole,
              fileName: outputFileName,
              absolutePath: outputPath,
              extension: '.pdf',
              fileSizeBytes: fileSizeBytes,
              sha256Hash: Value(pdfSha256),
              mimeType: const Value('application/pdf'),
              fileHealthKey: const Value('healthy'),
              createdAt: nowIso,
              updatedAt: nowIso,
            ),
          );
      await (_db.update(
        _db.fileConversions,
      )..where((c) => c.id.equals(conversionId))).write(
        FileConversionsCompanion(
          statusKey: const Value(_needsReviewStatus),
          outputFileId: Value(outputFileId),
          completedAt: Value(nowIso),
          updatedAt: Value(nowIso),
        ),
      );
      await _db
          .into(_db.fileEvents)
          .insert(
            FileEventsCompanion.insert(
              documentId: Value(documentId),
              fileId: Value(outputFileId),
              eventTypeKey: _conversionCompletedEvent,
              operationId: operationId,
              resultKey: _succeededResultKey,
              createdAt: nowIso,
            ),
          );
      return outputFileId;
    });
  }

  @override
  Future<void> recordFailedConversion({
    required int conversionId,
    required int documentId,
    required int sourceFileId,
    required String errorCode,
    required String errorMessageSafe,
    required String operationId,
    required String nowIso,
  }) {
    return _db.transaction(() async {
      await (_db.update(
        _db.fileConversions,
      )..where((c) => c.id.equals(conversionId))).write(
        FileConversionsCompanion(
          statusKey: const Value(_conversionFailedStatus),
          errorCode: Value(errorCode),
          errorMessageSafe: Value(errorMessageSafe),
          completedAt: Value(nowIso),
          updatedAt: Value(nowIso),
        ),
      );
      await _db
          .into(_db.fileEvents)
          .insert(
            FileEventsCompanion.insert(
              documentId: Value(documentId),
              fileId: Value(sourceFileId),
              eventTypeKey: _conversionFailedEvent,
              operationId: operationId,
              resultKey: _failedResultKey,
              createdAt: nowIso,
            ),
          );
    });
  }

  // ── P1.4 review methods ───────────────────────────────────────────────────

  @override
  Future<List<ConversionReviewItem>> loadPendingConversionReviews() async {
    final rows = await _db
        .customSelect(
          'SELECT fc.id AS conv_id, fc.document_id, fc.source_file_id, '
          'fc.output_file_id, fc.converter_key, fc.completed_at, fc.created_at, '
          'src.file_name AS src_name, src.absolute_path AS src_path, '
          'out.file_name AS out_name, out.absolute_path AS out_path '
          'FROM file_conversions fc '
          'JOIN document_files src ON src.id = fc.source_file_id '
          'JOIN document_files out ON out.id = fc.output_file_id '
          "WHERE fc.status_key = '$_needsReviewStatus' "
          'ORDER BY fc.created_at DESC',
          readsFrom: {_db.fileConversions, _db.documentFiles},
        )
        .get();

    return rows.map((row) {
      return ConversionReviewItem(
        conversionId: row.read<int>('conv_id'),
        documentId: row.read<int>('document_id'),
        sourceFileId: row.read<int>('source_file_id'),
        outputFileId: row.read<int>('output_file_id'),
        sourceFileName: row.read<String>('src_name'),
        sourcePath: row.read<String>('src_path'),
        outputFileName: row.read<String>('out_name'),
        outputPath: row.read<String>('out_path'),
        converterKey: row.readNullable<String>('converter_key'),
        completedAt: row.readNullable<String>('completed_at'),
        createdAt: row.read<String>('created_at'),
      );
    }).toList();
  }

  @override
  Future<bool> approveConversionReview({
    required int conversionId,
    required String nowIso,
  }) async {
    final rowsUpdated =
        await (_db.update(_db.fileConversions)..where(
              (c) =>
                  c.id.equals(conversionId) &
                  c.statusKey.equals(_needsReviewStatus),
            ))
            .write(
              FileConversionsCompanion(
                statusKey: const Value(_conversionApprovedStatus),
                qualityApproved: const Value(true),
                qualityReviewedAt: Value(nowIso),
                updatedAt: Value(nowIso),
              ),
            );
    return rowsUpdated > 0;
  }

  @override
  Future<bool> rejectConversionReview({
    required int conversionId,
    required String nowIso,
    String? reviewNote,
  }) async {
    final rowsUpdated =
        await (_db.update(_db.fileConversions)..where(
              (c) =>
                  c.id.equals(conversionId) &
                  c.statusKey.equals(_needsReviewStatus),
            ))
            .write(
              FileConversionsCompanion(
                statusKey: const Value(_conversionFailedStatus),
                qualityApproved: const Value(false),
                qualityReviewedAt: Value(nowIso),
                errorCode: const Value(_reviewRejectedErrorCode),
                errorMessageSafe: Value(reviewNote),
                updatedAt: Value(nowIso),
              ),
            );
    return rowsUpdated > 0;
  }

  // ── Document code allocation ───────────────────────────────────────────────

  @override
  Future<String> allocateDocumentCode(int documentId) {
    return _db.transaction(() async {
      final existing = await (_db.select(
        _db.documents,
      )..where((d) => d.id.equals(documentId))).getSingle();
      if (existing.documentCode != null) return existing.documentCode!;

      final allCodes =
          await (_db.selectOnly(_db.documents)
                ..addColumns([_db.documents.documentCode])
                ..where(_db.documents.documentCode.isNotNull()))
              .get();

      int maxNum = 0;
      for (final row in allCodes) {
        final code = row.read(_db.documents.documentCode);
        if (code != null) {
          final match = RegExp(r'^DOC-(\d{7})$').firstMatch(code);
          if (match != null) {
            final n = int.tryParse(match.group(1)!) ?? 0;
            if (n > maxNum) maxNum = n;
          }
        }
      }

      if (maxNum >= 9999999) throw StateError('document code space exhausted');
      final nextCode = 'DOC-${(maxNum + 1).toString().padLeft(7, '0')}';

      await (_db.update(_db.documents)..where((d) => d.id.equals(documentId)))
          .write(DocumentsCompanion(documentCode: Value(nextCode)));
      return nextCode;
    });
  }

  @override
  Future<List<ConversionWorkItem>> loadConversionWorkQueue() async {
    final rows = await _db
        .customSelect(
          'SELECT fc.id AS conv_id, fc.document_id, fc.source_file_id, '
          'fc.status_key, fc.error_code, fc.error_message_safe, '
          'fc.created_at, fc.updated_at, '
          'src.file_name AS src_name, src.absolute_path AS src_path '
          'FROM file_conversions fc '
          'JOIN document_files src ON src.id = fc.source_file_id '
          "WHERE fc.status_key IN ('$_pendingConversionStatus', "
          "'$_convertingStatus', '$_conversionFailedStatus') "
          'AND fc.id = ('
          'SELECT MAX(latest.id) FROM file_conversions latest '
          'WHERE latest.source_file_id = fc.source_file_id'
          ') '
          'ORDER BY fc.created_at DESC',
          readsFrom: {_db.fileConversions, _db.documentFiles},
        )
        .get();

    return rows.map((row) {
      return ConversionWorkItem(
        conversionId: row.read<int>('conv_id'),
        documentId: row.read<int>('document_id'),
        sourceFileId: row.read<int>('source_file_id'),
        sourceFileName: row.read<String>('src_name'),
        sourcePath: row.read<String>('src_path'),
        statusKey: row.read<String>('status_key'),
        errorCode: row.readNullable<String>('error_code'),
        errorMessageSafe: row.readNullable<String>('error_message_safe'),
        createdAt: row.read<String>('created_at'),
        updatedAt: row.readNullable<String>('updated_at'),
      );
    }).toList();
  }
}
