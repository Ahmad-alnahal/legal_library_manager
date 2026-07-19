// lib/features/import/data/repositories/drift_import_repository.dart

import 'package:drift/drift.dart';

import '../../../../core/database/app_database.dart';
import '../../domain/entities/import_batch_record.dart';
import '../../domain/entities/import_batch_report.dart';
import '../../domain/entities/import_error.dart';
import '../../domain/entities/import_file_result.dart';
import '../../domain/entities/prepared_source_file.dart';
import '../../domain/repositories/import_repository.dart';

/// Drift-backed [ImportRepository].
///
/// All Drift row/companion types stay inside this class. Each per-file method
/// runs in a single transaction so a failure rolls back only that file's partial
/// changes. No method ever writes, moves, renames, or deletes a source file —
/// it only records database references and safe audit events.
class DriftImportRepository implements ImportRepository {
  DriftImportRepository(this._db);

  final AppDatabase _db;

  static const String _sourceRole = 'source_original';

  /// `settings` keys for the durable, monotonic code allocators.
  static const String _seqImportBatch = 'seq.import_batch';
  static const String _seqDuplicateGroup = 'seq.duplicate_group';

  // --- Batch lifecycle ---

  @override
  Future<ImportBatchRef> createBatch({
    required String sourceFolder,
    required bool recursive,
    required DateTime now,
  }) {
    final String nowIso = now.toUtc().toIso8601String();
    return _db.transaction(() async {
      final int next = await _allocateSequence(
        _seqImportBatch,
        nowIso,
        currentMaxSuffix: () async => _maxNumericSuffix(
          (await _db.select(_db.importBatches).get()).map((b) => b.batchCode),
        ),
      );
      final String code = 'IMPORT-${next.toString().padLeft(7, '0')}';
      final int id = await _db
          .into(_db.importBatches)
          .insert(
            ImportBatchesCompanion.insert(
              batchCode: code,
              sourceFolder: sourceFolder,
              recursiveScan: recursive,
              statusKey: ImportBatchStatus.running.key,
              startedAt: nowIso,
            ),
          );
      return ImportBatchRef(id: id, batchCode: code);
    });
  }

  @override
  Future<void> updateBatchProgress(
    int batchId, {
    int? discoveredCount,
    int? importedCount,
    int? duplicateCount,
    int? failedCount,
    int? pairedCount,
    ImportBatchStatus? status,
    bool clearCompletedAt = false,
  }) {
    return (_db.update(
      _db.importBatches,
    )..where((b) => b.id.equals(batchId))).write(
      ImportBatchesCompanion(
        discoveredCount: _intOrAbsent(discoveredCount),
        importedCount: _intOrAbsent(importedCount),
        duplicateCount: _intOrAbsent(duplicateCount),
        failedCount: _intOrAbsent(failedCount),
        pairedCount: _intOrAbsent(pairedCount),
        statusKey: status == null ? const Value.absent() : Value(status.key),
        completedAt: clearCompletedAt
            ? const Value(null)
            : const Value.absent(),
      ),
    );
  }

  @override
  Future<void> completeBatch(
    int batchId, {
    required int discoveredCount,
    required int importedCount,
    required int duplicateCount,
    required int failedCount,
    required int pairedCount,
    required DateTime now,
  }) {
    return (_db.update(
      _db.importBatches,
    )..where((b) => b.id.equals(batchId))).write(
      ImportBatchesCompanion(
        statusKey: Value(ImportBatchStatus.completed.key),
        discoveredCount: Value(discoveredCount),
        importedCount: Value(importedCount),
        duplicateCount: Value(duplicateCount),
        failedCount: Value(failedCount),
        pairedCount: Value(pairedCount),
        completedAt: Value(now.toUtc().toIso8601String()),
      ),
    );
  }

  @override
  Future<void> failBatch(int batchId, {required DateTime now}) =>
      _finishBatch(batchId, ImportBatchStatus.failed, now);

  @override
  Future<void> cancelBatch(int batchId, {required DateTime now}) =>
      _finishBatch(batchId, ImportBatchStatus.cancelled, now);

  @override
  Future<void> markInterruptedBatches({required DateTime now}) {
    return (_db.update(
      _db.importBatches,
    )..where((b) => b.statusKey.equals(ImportBatchStatus.running.key))).write(
      ImportBatchesCompanion(
        statusKey: Value(ImportBatchStatus.interrupted.key),
        completedAt: Value(now.toUtc().toIso8601String()),
      ),
    );
  }

  // --- History ---

  @override
  Future<List<ImportBatchRecord>> getRecentBatches({int limit = 20}) async {
    final query = _db.select(_db.importBatches)
      ..orderBy([(t) => OrderingTerm.desc(t.startedAt)])
      ..limit(limit);
    final rows = await query.get();
    return rows.map(_toBatchRecord).toList();
  }

  ImportBatchRecord _toBatchRecord(ImportBatch row) {
    return ImportBatchRecord(
      id: row.id,
      batchCode: row.batchCode,
      sourceFolder: row.sourceFolder,
      status: ImportBatchStatus.values.firstWhere(
        (s) => s.key == row.statusKey,
        orElse: () => ImportBatchStatus.failed,
      ),
      discoveredCount: row.discoveredCount,
      importedCount: row.importedCount,
      duplicateCount: row.duplicateCount,
      failedCount: row.failedCount,
      pairedCount: row.pairedCount,
      startedAt: DateTime.parse(row.startedAt),
      completedAt: row.completedAt != null
          ? DateTime.parse(row.completedAt!)
          : null,
    );
  }

  Future<void> _finishBatch(
    int batchId,
    ImportBatchStatus status,
    DateTime now,
  ) {
    return (_db.update(
      _db.importBatches,
    )..where((b) => b.id.equals(batchId))).write(
      ImportBatchesCompanion(
        statusKey: Value(status.key),
        completedAt: Value(now.toUtc().toIso8601String()),
      ),
    );
  }

  // --- Identity lookup (Windows case-insensitive) ---

  @override
  Future<ExistingFileRef?> findByAbsolutePath(String canonicalPath) async {
    final DocumentFile? row = await _findFileByPath(canonicalPath);
    if (row == null) return null;
    return ExistingFileRef(fileId: row.id, documentId: row.documentId);
  }

  Future<DocumentFile?> _findFileByPath(String canonicalPath) {
    final String target = canonicalPath.toLowerCase();
    return (_db.select(
      _db.documentFiles,
    )..where((f) => f.absolutePath.lower().equals(target))).getSingleOrNull();
  }

  // --- Per-file persistence ---

  @override
  Future<ImportFileResult> persistHashedFile(
    PreparedSourceFile file, {
    required String operationId,
    required DateTime now,
    int? batchId,
  }) {
    final String nowIso = now.toUtc().toIso8601String();
    return _db.transaction(() async {
      final DocumentFile? existing = await _findFileByPath(file.canonicalPath);
      if (existing != null) {
        // A completed (hashed) row for this exact path stays already_imported.
        if (existing.sha256Hash != null) {
          return _recordAlreadyImported(
            existing,
            operationId: operationId,
            nowIso: nowIso,
            batchId: batchId,
          );
        }
        // A previously-failed row (null hash) for this path is retried in place.
        return _retryExistingFailed(
          existing,
          file,
          operationId: operationId,
          nowIso: nowIso,
          batchId: batchId,
        );
      }

      final List<DocumentFile> sameHash = await (_db.select(
        _db.documentFiles,
      )..where((f) => f.sha256Hash.equals(file.sha256))).get();

      if (sameHash.isEmpty) {
        return _insertNewDocumentAndFile(
          file,
          operationId: operationId,
          nowIso: nowIso,
          batchId: batchId,
        );
      }
      return _attachDuplicate(
        file,
        sameHash: sameHash,
        operationId: operationId,
        nowIso: nowIso,
        batchId: batchId,
      );
    });
  }

  @override
  Future<ImportFileResult> persistFailedFile(
    FailedSourceFile file, {
    required ImportFileOutcome outcome,
    required String operationId,
    required DateTime now,
    int? batchId,
  }) {
    final String nowIso = now.toUtc().toIso8601String();
    return _db.transaction(() async {
      final DocumentFile? existing = await _findFileByPath(file.canonicalPath);
      if (existing != null) {
        // A completed row stays already_imported; a still-failed row is
        // refreshed in place (no second physical row for the same path).
        if (existing.sha256Hash != null) {
          return _recordAlreadyImported(
            existing,
            operationId: operationId,
            nowIso: nowIso,
            batchId: batchId,
          );
        }
        return _refreshFailedRow(
          existing,
          file,
          outcome: outcome,
          operationId: operationId,
          nowIso: nowIso,
          batchId: batchId,
        );
      }

      final int documentId = await _insertDocument(nowIso);
      final int fileId = await _db
          .into(_db.documentFiles)
          .insert(
            DocumentFilesCompanion.insert(
              documentId: documentId,
              fileRoleKey: _sourceRole,
              fileName: file.displayName,
              absolutePath: file.canonicalPath,
              extension: file.extension,
              fileSizeBytes: file.sizeBytes,
              createdAt: nowIso,
              updatedAt: nowIso,
              mimeType: Value(file.mimeType),
              fileHealthKey: Value(file.health.key),
              isReadOnlySource: const Value(true),
              importedAt: Value(nowIso),
              existsLastChecked: const Value(true),
              lastCheckedAt: Value(nowIso),
            ),
          );

      await _insertEvent(
        documentId: documentId,
        fileId: fileId,
        eventType: 'hash_failed',
        result: 'failed',
        operationId: operationId,
        nowIso: nowIso,
        sourcePath: file.canonicalPath,
        errorCode: file.errorCode,
        messageSafe: file.safeMessage,
      );

      if (batchId != null) {
        await _attachBatchFile(batchId, fileId, outcome, nowIso);
      }
      return ImportFileResult(
        outcome: outcome,
        documentId: documentId,
        fileId: fileId,
      );
    });
  }

  @override
  Future<ImportFileResult> recordFilelessOutcome({
    required ImportFileOutcome outcome,
    required String sourcePath,
    required String operationId,
    required DateTime now,
    String? errorCode,
    String? safeMessage,
  }) {
    final String nowIso = now.toUtc().toIso8601String();
    final String result = outcome == ImportFileOutcome.unsupportedType
        ? 'warning'
        : 'failed';
    return _db.transaction(() async {
      await _insertEvent(
        documentId: null,
        fileId: null,
        eventType: 'discovered',
        result: result,
        operationId: operationId,
        nowIso: nowIso,
        sourcePath: sourcePath,
        errorCode: errorCode ?? outcome.key,
        messageSafe: safeMessage,
      );
      return ImportFileResult(outcome: outcome);
    });
  }

  @override
  Future<ImportFileResult> persistPairedWordSource(
    PreparedSourceFile file, {
    required int existingDocumentId,
    required String operationId,
    required DateTime now,
    int? batchId,
  }) {
    final String nowIso = now.toUtc().toIso8601String();
    return _db.transaction(() async {
      final DocumentFile? existing = await _findFileByPath(file.canonicalPath);
      if (existing != null) {
        return _recordAlreadyImported(
          existing,
          operationId: operationId,
          nowIso: nowIso,
          batchId: batchId,
        );
      }

      final int fileId = await _insertSourceFile(
        existingDocumentId,
        file,
        nowIso,
      );

      await _insertEvent(
        documentId: existingDocumentId,
        fileId: fileId,
        eventType: 'paired_source_detected',
        result: 'succeeded',
        operationId: operationId,
        nowIso: nowIso,
        sourcePath: file.canonicalPath,
        actualSha256: file.sha256,
      );

      if (batchId != null) {
        await _attachBatchFile(
          batchId,
          fileId,
          ImportFileOutcome.pairedWordSource,
          nowIso,
        );
      }
      return ImportFileResult(
        outcome: ImportFileOutcome.pairedWordSource,
        documentId: existingDocumentId,
        fileId: fileId,
      );
    });
  }

  // --- internal helpers (Drift types only) ---

  /// Same exact path, already successfully imported: updates last-checked
  /// metadata only, records an `existence_checked` event, returns
  /// `already_imported`.
  Future<ImportFileResult> _recordAlreadyImported(
    DocumentFile existing, {
    required String operationId,
    required String nowIso,
    required int? batchId,
  }) async {
    await (_db.update(
      _db.documentFiles,
    )..where((f) => f.id.equals(existing.id))).write(
      DocumentFilesCompanion(
        existsLastChecked: const Value(true),
        lastCheckedAt: Value(nowIso),
        updatedAt: Value(nowIso),
      ),
    );
    await _insertEvent(
      documentId: existing.documentId,
      fileId: existing.id,
      eventType: 'existence_checked',
      result: 'succeeded',
      operationId: operationId,
      nowIso: nowIso,
      sourcePath: existing.absolutePath,
    );
    if (batchId != null) {
      await _attachBatchFile(
        batchId,
        existing.id,
        ImportFileOutcome.alreadyImported,
        nowIso,
      );
    }
    return ImportFileResult(
      outcome: ImportFileOutcome.alreadyImported,
      documentId: existing.documentId,
      fileId: existing.id,
    );
  }

  /// Retries a previously-failed (null-hash) row in place after a successful
  /// re-hash. Updates the existing physical record with the recalculated hash,
  /// health, size, page count, MIME, and last-checked metadata — never creating
  /// a second row for the same path and never touching the source file on disk.
  ///
  /// Finalized duplicate identity: if the recalculated hash matches files on an
  /// existing logical document, the retried file's `document_id` is reassigned to
  /// the canonical existing document (the document of the lowest-id matching file
  /// among the others — the same deterministic rule as normal duplicate import),
  /// every matching physical file is attached to that one document, and all are
  /// members of the one duplicate group.
  ///
  /// Placeholder handling (transactional): the failed retain created a minimum
  /// placeholder document for this file. After reassignment it is empty. If it
  /// carries no business metadata or dependent business records, it is removed as
  /// internal failed-import placeholder cleanup (its audit events are re-pointed
  /// to the canonical document first, preserving traceability). Otherwise it is
  /// preserved and a structured [ImportErrorCode.duplicateIdentityConflict] is
  /// reported — identity is still satisfied because the physical file was
  /// reassigned. No source physical-file record is ever deleted.
  Future<ImportFileResult> _retryExistingFailed(
    DocumentFile existing,
    PreparedSourceFile file, {
    required String operationId,
    required String nowIso,
    required int? batchId,
  }) async {
    await (_db.update(
      _db.documentFiles,
    )..where((f) => f.id.equals(existing.id))).write(
      DocumentFilesCompanion(
        fileName: Value(file.displayName),
        extension: Value(file.extension),
        fileSizeBytes: Value(file.sizeBytes),
        sha256Hash: Value(file.sha256),
        pageCount: Value(file.pageCount),
        mimeType: Value(file.mimeType),
        fileHealthKey: Value(file.health.key),
        existsLastChecked: const Value(true),
        lastCheckedAt: Value(nowIso),
        importedAt: Value(nowIso),
        updatedAt: Value(nowIso),
      ),
    );

    // Other physical files (on any document) already carrying this hash.
    final List<DocumentFile> others =
        (await (_db.select(
              _db.documentFiles,
            )..where((f) => f.sha256Hash.equals(file.sha256))).get())
            .where((f) => f.id != existing.id)
            .toList();

    // Unique content after retry: keep the file on its own (now real) document.
    if (others.isEmpty) {
      await _db.updateDocumentFts(existing.documentId);
      await _insertEvent(
        documentId: existing.documentId,
        fileId: existing.id,
        eventType: 'imported',
        result: 'succeeded',
        operationId: operationId,
        nowIso: nowIso,
        sourcePath: existing.absolutePath,
        actualSha256: file.sha256,
        messageSafe: 'retry',
      );
      if (batchId != null) {
        await _attachBatchFile(
          batchId,
          existing.id,
          ImportFileOutcome.importedNew,
          nowIso,
        );
      }
      return ImportFileResult(
        outcome: ImportFileOutcome.importedNew,
        documentId: existing.documentId,
        fileId: existing.id,
      );
    }

    // Duplicate: reassign onto the canonical existing logical document.
    others.sort((a, b) => a.id.compareTo(b.id));
    final int canonicalDocId = others.first.documentId;
    final int placeholderDocId = existing.documentId;

    // Attach every matching physical file (including the retried one) to the one
    // canonical document.
    final List<DocumentFile> allMatching = await (_db.select(
      _db.documentFiles,
    )..where((f) => f.sha256Hash.equals(file.sha256))).get();
    for (final DocumentFile f in allMatching) {
      if (f.documentId == canonicalDocId) continue;
      await (_db.update(
        _db.documentFiles,
      )..where((d) => d.id.equals(f.id))).write(
        DocumentFilesCompanion(
          documentId: Value(canonicalDocId),
          updatedAt: Value(nowIso),
        ),
      );
    }

    await _ensureDuplicateGroupForHash(file.sha256, nowIso);
    await _db.updateDocumentFts(canonicalDocId);

    // Placeholder cleanup or safe conflict.
    ImportError? conflict;
    if (placeholderDocId != canonicalDocId) {
      if (await _documentHasBusinessMeaning(placeholderDocId)) {
        conflict = const ImportError(
          code: ImportErrorCode.duplicateIdentityConflict,
          message: 'placeholder document retained: has business metadata',
        );
        await _insertEvent(
          documentId: canonicalDocId,
          fileId: existing.id,
          eventType: 'imported',
          result: 'warning',
          operationId: operationId,
          nowIso: nowIso,
          sourcePath: existing.absolutePath,
          actualSha256: file.sha256,
          errorCode: 'duplicate_identity_conflict',
          messageSafe: 'placeholder_retained',
        );
      } else {
        await _deleteEmptyPlaceholder(placeholderDocId, canonicalDocId);
      }
    }

    await _insertEvent(
      documentId: canonicalDocId,
      fileId: existing.id,
      eventType: 'imported',
      result: 'succeeded',
      operationId: operationId,
      nowIso: nowIso,
      sourcePath: existing.absolutePath,
      actualSha256: file.sha256,
      messageSafe: 'retry_duplicate_path',
    );
    if (batchId != null) {
      await _attachBatchFile(
        batchId,
        existing.id,
        ImportFileOutcome.importedDuplicatePath,
        nowIso,
      );
    }
    return ImportFileResult(
      outcome: ImportFileOutcome.importedDuplicatePath,
      documentId: canonicalDocId,
      fileId: existing.id,
      error: conflict,
    );
  }

  /// True when [documentId] carries any business metadata or dependent business
  /// records, so it must not be removed as a placeholder. Audit `file_events`
  /// are not business records (they are re-pointed during cleanup).
  Future<bool> _documentHasBusinessMeaning(int documentId) async {
    // Remaining physical files keep the document alive.
    final int fileCount = (await (_db.select(
      _db.documentFiles,
    )..where((f) => f.documentId.equals(documentId))).get()).length;
    if (fileCount > 0) return true;

    final Document? doc = await (_db.select(
      _db.documents,
    )..where((d) => d.id.equals(documentId))).getSingleOrNull();
    if (doc == null) return false;
    final bool meaningfulFields =
        doc.documentCode != null ||
        doc.documentTypeId != null ||
        doc.title != null ||
        doc.primaryMainCategoryId != null ||
        doc.primarySubCategoryId != null ||
        doc.languageKey != null ||
        doc.countryKey != null ||
        doc.publicationYear != null ||
        doc.summary != null ||
        doc.sourceDescription != null ||
        doc.reviewNotes != null ||
        doc.classifiedAt != null ||
        doc.copiedToLibraryAt != null ||
        doc.readyForExportAt != null ||
        doc.archivedAt != null ||
        doc.workflowStatusKey != 'imported' ||
        // Reference values changed from their schema defaults are meaningful.
        doc.trustLevelKey != 'unverified' ||
        doc.usageRightsKey != 'unknown' ||
        doc.metadataQualityKey != 'low';
    if (meaningfulFields) return true;

    final bool hasClassifications = (await (_db.select(
      _db.documentClassifications,
    )..where((c) => c.documentId.equals(documentId))).get()).isNotEmpty;
    if (hasClassifications) return true;
    final bool hasKeywords = (await (_db.select(
      _db.documentKeywords,
    )..where((k) => k.documentId.equals(documentId))).get()).isNotEmpty;
    if (hasKeywords) return true;
    final bool hasConversions = (await (_db.select(
      _db.fileConversions,
    )..where((c) => c.documentId.equals(documentId))).get()).isNotEmpty;
    if (hasConversions) return true;
    final bool hasExportLinks = (await (_db.select(
      _db.exportBatchDocuments,
    )..where((e) => e.documentId.equals(documentId))).get()).isNotEmpty;
    if (hasExportLinks) return true;

    bool hasDetails = false;
    hasDetails |= (await (_db.select(
      _db.bookDetails,
    )..where((d) => d.documentId.equals(documentId))).get()).isNotEmpty;
    hasDetails |= (await (_db.select(
      _db.thesisDetails,
    )..where((d) => d.documentId.equals(documentId))).get()).isNotEmpty;
    hasDetails |= (await (_db.select(
      _db.researchDetails,
    )..where((d) => d.documentId.equals(documentId))).get()).isNotEmpty;
    hasDetails |= (await (_db.select(
      _db.legislationDetails,
    )..where((d) => d.documentId.equals(documentId))).get()).isNotEmpty;
    hasDetails |= (await (_db.select(
      _db.courtCaseDetails,
    )..where((d) => d.documentId.equals(documentId))).get()).isNotEmpty;
    hasDetails |= (await (_db.select(
      _db.reportDetails,
    )..where((d) => d.documentId.equals(documentId))).get()).isNotEmpty;
    return hasDetails;
  }

  /// Re-points the placeholder document's audit events to the canonical document
  /// (preserving traceability), then deletes the now-empty placeholder document.
  /// Only called once [_documentHasBusinessMeaning] is false.
  Future<void> _deleteEmptyPlaceholder(
    int placeholderDocId,
    int canonicalDocId,
  ) async {
    await (_db.update(_db.fileEvents)
          ..where((e) => e.documentId.equals(placeholderDocId)))
        .write(FileEventsCompanion(documentId: Value(canonicalDocId)));
    await (_db.delete(
      _db.documents,
    )..where((d) => d.id.equals(placeholderDocId))).go();
  }

  /// Refreshes an existing still-failing row for the same path: updates health,
  /// size, and last-checked metadata, records a safe failure event, and returns
  /// the failure outcome — never creating a second row, never grouping.
  Future<ImportFileResult> _refreshFailedRow(
    DocumentFile existing,
    FailedSourceFile file, {
    required ImportFileOutcome outcome,
    required String operationId,
    required String nowIso,
    required int? batchId,
  }) async {
    await (_db.update(
      _db.documentFiles,
    )..where((f) => f.id.equals(existing.id))).write(
      DocumentFilesCompanion(
        fileSizeBytes: Value(file.sizeBytes),
        fileHealthKey: Value(file.health.key),
        existsLastChecked: const Value(true),
        lastCheckedAt: Value(nowIso),
        updatedAt: Value(nowIso),
      ),
    );
    await _insertEvent(
      documentId: existing.documentId,
      fileId: existing.id,
      eventType: 'hash_failed',
      result: 'failed',
      operationId: operationId,
      nowIso: nowIso,
      sourcePath: existing.absolutePath,
      errorCode: file.errorCode,
      messageSafe: file.safeMessage,
    );
    if (batchId != null) {
      await _attachBatchFile(batchId, existing.id, outcome, nowIso);
    }
    return ImportFileResult(
      outcome: outcome,
      documentId: existing.documentId,
      fileId: existing.id,
    );
  }

  Future<ImportFileResult> _insertNewDocumentAndFile(
    PreparedSourceFile file, {
    required String operationId,
    required String nowIso,
    required int? batchId,
  }) async {
    final int documentId = await _insertDocument(nowIso);
    final int fileId = await _insertSourceFile(documentId, file, nowIso);
    await _db.updateDocumentFts(documentId);

    await _insertEvent(
      documentId: documentId,
      fileId: fileId,
      eventType: 'discovered',
      result: 'started',
      operationId: operationId,
      nowIso: nowIso,
      sourcePath: file.canonicalPath,
    );
    await _insertEvent(
      documentId: documentId,
      fileId: fileId,
      eventType: 'imported',
      result: 'succeeded',
      operationId: operationId,
      nowIso: nowIso,
      sourcePath: file.canonicalPath,
      actualSha256: file.sha256,
    );

    if (batchId != null) {
      await _attachBatchFile(
        batchId,
        fileId,
        ImportFileOutcome.importedNew,
        nowIso,
      );
    }
    return ImportFileResult(
      outcome: ImportFileOutcome.importedNew,
      documentId: documentId,
      fileId: fileId,
    );
  }

  Future<ImportFileResult> _attachDuplicate(
    PreparedSourceFile file, {
    required List<DocumentFile> sameHash,
    required String operationId,
    required String nowIso,
    required int? batchId,
  }) async {
    // All same-hash files share one logical document by the first-import
    // identity rule; use the existing document of the lowest-id matching file.
    sameHash.sort((a, b) => a.id.compareTo(b.id));
    final int documentId = sameHash.first.documentId;
    final int fileId = await _insertSourceFile(documentId, file, nowIso);

    await _ensureDuplicateGroupForHash(file.sha256, nowIso);

    await _insertEvent(
      documentId: documentId,
      fileId: fileId,
      eventType: 'imported',
      result: 'succeeded',
      operationId: operationId,
      nowIso: nowIso,
      sourcePath: file.canonicalPath,
      actualSha256: file.sha256,
      messageSafe: 'duplicate_path',
    );

    if (batchId != null) {
      await _attachBatchFile(
        batchId,
        fileId,
        ImportFileOutcome.importedDuplicatePath,
        nowIso,
      );
    }
    return ImportFileResult(
      outcome: ImportFileOutcome.importedDuplicatePath,
      documentId: documentId,
      fileId: fileId,
    );
  }

  /// Creates or reuses exactly one duplicate group for [sha] and ensures every
  /// physical file currently carrying that hash (across all logical documents)
  /// is a member. Never deletes or hides members. Returns the group id.
  Future<int> _ensureDuplicateGroupForHash(String sha, String nowIso) async {
    final DuplicateGroup? group = await (_db.select(
      _db.duplicateGroups,
    )..where((g) => g.sha256Hash.equals(sha))).getSingleOrNull();

    final int groupId;
    if (group == null) {
      final int next = await _allocateSequence(
        _seqDuplicateGroup,
        nowIso,
        currentMaxSuffix: () async => _maxNumericSuffix(
          (await _db.select(_db.duplicateGroups).get()).map((g) => g.groupCode),
        ),
      );
      final String groupCode = 'DUP-GROUP-${next.toString().padLeft(5, '0')}';
      groupId = await _db
          .into(_db.duplicateGroups)
          .insert(
            DuplicateGroupsCompanion.insert(
              groupCode: groupCode,
              sha256Hash: sha,
              createdAt: nowIso,
              updatedAt: nowIso,
            ),
          );
    } else {
      groupId = group.id;
      await (_db.update(_db.duplicateGroups)
            ..where((g) => g.id.equals(groupId)))
          .write(DuplicateGroupsCompanion(updatedAt: Value(nowIso)));
    }

    final List<DocumentFile> allMatching = await (_db.select(
      _db.documentFiles,
    )..where((f) => f.sha256Hash.equals(sha))).get();
    final List<DuplicateGroupMember> members = await (_db.select(
      _db.duplicateGroupMembers,
    )..where((m) => m.duplicateGroupId.equals(groupId))).get();
    final Set<int> memberIds = members.map((m) => m.fileId).toSet();
    for (final DocumentFile f in allMatching) {
      if (memberIds.contains(f.id)) continue;
      await _db
          .into(_db.duplicateGroupMembers)
          .insert(
            DuplicateGroupMembersCompanion.insert(
              duplicateGroupId: groupId,
              fileId: f.id,
              addedAt: nowIso,
            ),
          );
    }
    return groupId;
  }

  Future<int> _insertDocument(String nowIso) => _db
      .into(_db.documents)
      .insert(DocumentsCompanion.insert(createdAt: nowIso, updatedAt: nowIso));

  Future<int> _insertSourceFile(
    int documentId,
    PreparedSourceFile file,
    String nowIso,
  ) {
    return _db
        .into(_db.documentFiles)
        .insert(
          DocumentFilesCompanion.insert(
            documentId: documentId,
            fileRoleKey: _sourceRole,
            fileName: file.displayName,
            absolutePath: file.canonicalPath,
            extension: file.extension,
            fileSizeBytes: file.sizeBytes,
            createdAt: nowIso,
            updatedAt: nowIso,
            mimeType: Value(file.mimeType),
            sha256Hash: Value(file.sha256),
            pageCount: Value(file.pageCount),
            fileHealthKey: Value(file.health.key),
            isReadOnlySource: const Value(true),
            importedAt: Value(nowIso),
            existsLastChecked: const Value(true),
            lastCheckedAt: Value(nowIso),
          ),
        );
  }

  Future<void> _attachBatchFile(
    int batchId,
    int fileId,
    ImportFileOutcome outcome,
    String nowIso,
  ) {
    // Upsert on the composite primary key (import_batch_id, file_id) so
    // re-processing/retrying the same file within one batch updates its result
    // instead of throwing a composite-PK violation.
    return _db
        .into(_db.importBatchFiles)
        .insertOnConflictUpdate(
          ImportBatchFilesCompanion.insert(
            importBatchId: batchId,
            fileId: fileId,
            resultKey: outcome.key,
            createdAt: nowIso,
          ),
        );
  }

  Future<void> _insertEvent({
    required int? documentId,
    required int? fileId,
    required String eventType,
    required String result,
    required String operationId,
    required String nowIso,
    String? sourcePath,
    String? actualSha256,
    String? errorCode,
    String? messageSafe,
  }) {
    return _db
        .into(_db.fileEvents)
        .insert(
          FileEventsCompanion.insert(
            eventTypeKey: eventType,
            operationId: operationId,
            resultKey: result,
            createdAt: nowIso,
            documentId: Value(documentId),
            fileId: Value(fileId),
            sourcePath: Value(sourcePath),
            actualSha256: Value(actualSha256),
            errorCode: Value(errorCode),
            messageSafe: Value(messageSafe),
          ),
        );
  }

  /// Durable, monotonic, non-reusing sequence allocator backed by the existing
  /// `settings` table (no schema change). The last-issued value per counter is
  /// persisted, so a code is never reused even after the highest-numbered row is
  /// deleted. Allocation runs inside the caller's write transaction; drift
  /// serializes write transactions on the single connection, so concurrent
  /// creators each read-increment-persist atomically and receive distinct
  /// values. The UNIQUE code column remains the final backstop.
  ///
  /// Bootstrap safety: when the counter row does not yet exist (first use, or a
  /// database that already has codes from before this allocator existed), the
  /// starting point is seeded from the highest existing code suffix via
  /// [currentMaxSuffix], so a pre-existing code is never reused.
  ///
  /// Corruption safety: an existing counter holding a non-parseable/negative
  /// value throws instead of silently resetting to zero (which would reuse
  /// codes).
  Future<int> _allocateSequence(
    String counterKey,
    String nowIso, {
    required Future<int> Function() currentMaxSuffix,
  }) async {
    final Setting? row = await (_db.select(
      _db.settings,
    )..where((s) => s.key.equals(counterKey))).getSingleOrNull();

    final int base;
    if (row == null) {
      base = await currentMaxSuffix();
    } else {
      final int? parsed = int.tryParse(row.value);
      if (parsed == null || parsed < 0) {
        throw StateError(
          'Corrupt sequence counter "$counterKey"; refusing to reuse codes.',
        );
      }
      base = parsed;
    }

    final int next = base + 1;
    await _db
        .into(_db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: counterKey,
            value: next.toString(),
            updatedAt: nowIso,
          ),
        );
    return next;
  }

  /// Highest trailing numeric suffix among [codes], or 0 when none parse.
  int _maxNumericSuffix(Iterable<String> codes) {
    int maxN = 0;
    final RegExp trailing = RegExp(r'(\d+)$');
    for (final String code in codes) {
      final Match? m = trailing.firstMatch(code);
      if (m == null) continue;
      final int? n = int.tryParse(m.group(1)!);
      if (n != null && n > maxN) maxN = n;
    }
    return maxN;
  }

  Value<int> _intOrAbsent(int? value) =>
      value == null ? const Value.absent() : Value(value);
}
