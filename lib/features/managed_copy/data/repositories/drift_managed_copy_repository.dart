// lib/features/managed_copy/data/repositories/drift_managed_copy_repository.dart

import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/constants/domain_keys.dart';
import '../../../../core/database/app_database.dart';
import '../../../../core/time/clock.dart';
import '../../domain/entities/copy_roots.dart';
import '../../domain/entities/document_copy_state.dart';
import '../../domain/entities/managed_copy_persistence_data.dart';
import '../../domain/entities/managed_file_ref.dart';
import '../../domain/entities/source_file_candidate.dart';
import '../../domain/entities/startup_recovery_report.dart';
import '../../domain/repositories/managed_copy_repository.dart';

/// Drift-backed [ManagedCopyRepository].
///
/// Reads from [documents], [document_files], and [settings]; appends to
/// [file_events]; updates [documents] and inserts into [document_files].
/// Source file records are never mutated or deleted by any method here.
class DriftManagedCopyRepository implements ManagedCopyRepository {
  const DriftManagedCopyRepository(this._db, this._clock);

  final AppDatabase _db;
  final Clock _clock;

  static const String _managedLibraryKey = 'managed_library_root';
  static const String _backupRootKey = 'database_backup_root';
  static const String _exportRootKey = 'export_root';
  static const String _startupRecoveryStatusKey = 'startup_recovery_status';
  static const String _startupRecoveryArtifactCountKey =
      'startup_recovery_artifact_count';

  // ── Document state ─────────────────────────────────────────────────────────

  @override
  Future<DocumentCopyState?> loadDocumentState(int documentId) async {
    final rows = await (_db.select(
      _db.documents,
    )..where((d) => d.id.equals(documentId))).get();
    if (rows.isEmpty) return null;
    final doc = rows.first;

    final managedCopyRows =
        await (_db.select(_db.documentFiles)..where(
              (f) =>
                  f.documentId.equals(documentId) &
                  f.fileRoleKey.equals(FileRoleKey.managedCopy),
            ))
            .get();

    return DocumentCopyState(
      documentId: doc.id,
      workflowStatusKey: doc.workflowStatusKey,
      existingDocumentCode: doc.documentCode,
      hasManagedCopy: managedCopyRows.isNotEmpty,
      hasHealthyManagedCopy: managedCopyRows.any(
        (r) => r.fileHealthKey == FileHealthKey.healthy,
      ),
    );
  }

  // ── Settings / roots ───────────────────────────────────────────────────────

  @override
  Future<CopyRoots> loadCopyRoots() async {
    final managedLibraryRoot = await _setting(_managedLibraryKey);
    final backupRoot = await _setting(_backupRootKey);
    return CopyRoots(
      managedLibraryRoot: managedLibraryRoot,
      backupRoot: backupRoot,
    );
  }

  @override
  Future<void> saveCopyRoots({
    required String managedLibraryRoot,
    required String backupRoot,
  }) {
    return _db.transaction(() async {
      final now = _clock.nowUtc().toIso8601String();
      for (final entry in {
        _managedLibraryKey: managedLibraryRoot,
        _backupRootKey: backupRoot,
      }.entries) {
        await _db
            .into(_db.settings)
            .insertOnConflictUpdate(
              SettingsCompanion.insert(
                key: entry.key,
                value: entry.value,
                updatedAt: now,
              ),
            );
      }
    });
  }

  @override
  Future<String?> loadExportRoot() => _setting(_exportRootKey);

  @override
  Future<void> saveExportRoot(String path) async {
    await _db
        .into(_db.settings)
        .insertOnConflictUpdate(
          SettingsCompanion.insert(
            key: _exportRootKey,
            value: path,
            updatedAt: _clock.nowUtc().toIso8601String(),
          ),
        );
  }

  @override
  Future<String> loadDatabaseRoot() async {
    final dir = await getApplicationSupportDirectory();
    return dir.path;
  }

  @override
  Future<String> loadWordTempRoot() async {
    // getTemporaryDirectory() resolves to the OS per-user local temp folder
    // (on Windows: under %LOCALAPPDATA%\Temp), which is never OneDrive- or
    // cloud-sync-managed — unlike getApplicationSupportDirectory(), which can
    // resolve under a roaming profile subject to Known Folder Move policies.
    final dir = await getTemporaryDirectory();
    final base = dir.path.replaceAll('/', r'\');
    final trimmed = base.endsWith(r'\')
        ? base.substring(0, base.length - 1)
        : base;
    return '$trimmed\\MARJIY';
  }

  // ── Source file queries ────────────────────────────────────────────────────

  @override
  Future<List<String>> loadDocumentSourcePaths(int documentId) async {
    final rows =
        await (_db.select(_db.documentFiles)..where(
              (f) =>
                  f.documentId.equals(documentId) &
                  f.fileRoleKey.equals(FileRoleKey.sourceOriginal),
            ))
            .get();
    return rows.map((r) => r.absolutePath).toList(growable: false);
  }

  @override
  Future<List<String>> loadAllSourcePaths() async {
    final rows = await (_db.select(
      _db.documentFiles,
    )..where((f) => f.fileRoleKey.equals(FileRoleKey.sourceOriginal))).get();
    return rows.map((row) => row.absolutePath).toList(growable: false);
  }

  @override
  Future<List<String>> loadManagedDocumentCodes() async {
    final rows =
        await (_db.selectOnly(_db.documents)
              ..addColumns([_db.documents.documentCode])
              ..where(_db.documents.documentCode.isNotNull()))
            .get();
    return rows
        .map((row) => row.read(_db.documents.documentCode))
        .whereType<String>()
        .where((code) => RegExp(r'^DOC-[0-9]{7}$').hasMatch(code))
        .toSet()
        .toList()
      ..sort();
  }

  @override
  Future<void> saveStartupRecoveryReport(StartupRecoveryReport report) {
    return _db.transaction(() async {
      final now = _clock.nowUtc().toIso8601String();
      for (final entry in {
        _startupRecoveryStatusKey: report.status.name,
        _startupRecoveryArtifactCountKey: report.artifactCount.toString(),
      }.entries) {
        await _db
            .into(_db.settings)
            .insertOnConflictUpdate(
              SettingsCompanion.insert(
                key: entry.key,
                value: entry.value,
                updatedAt: now,
              ),
            );
      }
    });
  }

  @override
  Future<StartupRecoveryReport> loadStartupRecoveryReport() async {
    final rawStatus = await _setting(_startupRecoveryStatusKey);
    final status = StartupRecoveryStatus.values.where(
      (s) => s.name == rawStatus,
    );
    final parsedStatus = status.isEmpty
        ? StartupRecoveryStatus.healthy
        : status.first;
    final rawCount = await _setting(_startupRecoveryArtifactCountKey);
    final artifactCount = int.tryParse(rawCount ?? '') ?? 0;
    return StartupRecoveryReport(
      status: parsedStatus,
      artifactCount: artifactCount < 0 ? 0 : artifactCount,
    );
  }

  @override
  Future<List<SourceFileCandidate>> loadEligibleSources(int documentId) async {
    final rows =
        await (_db.select(_db.documentFiles)..where(
              (f) =>
                  f.documentId.equals(documentId) &
                  (f.fileRoleKey.equals(FileRoleKey.sourceOriginal) |
                      f.fileRoleKey.equals(FileRoleKey.convertedPdf)),
            ))
            .get();
    return rows
        .map(
          (r) => SourceFileCandidate(
            fileId: r.id,
            documentId: r.documentId,
            absolutePath: r.absolutePath,
            storedExtension: r.extension,
            fileHealthKey: r.fileHealthKey,
            // converted_pdf files are never preferred over a source_original PDF.
            isPreferred:
                r.fileRoleKey == FileRoleKey.sourceOriginal && r.isPreferred,
            sha256Hash: r.sha256Hash,
          ),
        )
        .toList(growable: false);
  }

  // ── Document code allocation ───────────────────────────────────────────────

  @override
  Future<String> allocateDocumentCode(int documentId) async {
    return _db.transaction(() async {
      // Reuse the existing code when already assigned.
      final existing = await (_db.select(
        _db.documents,
      )..where((d) => d.id.equals(documentId))).getSingle();
      if (existing.documentCode != null) return existing.documentCode!;

      // Derive next code from the maximum existing code, never from row count.
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

      if (maxNum >= 9999999) {
        throw StateError('Document code space exhausted.');
      }

      final newCode = 'DOC-${(maxNum + 1).toString().padLeft(7, '0')}';

      await (_db.update(
        _db.documents,
      )..where((d) => d.id.equals(documentId))).write(
        DocumentsCompanion(
          documentCode: Value(newCode),
          updatedAt: Value(_clock.nowUtc().toIso8601String()),
        ),
      );

      return newCode;
    });
  }

  // ── Event appending ────────────────────────────────────────────────────────

  @override
  Future<void> appendFileEvent({
    required int? documentId,
    required int? fileId,
    required String eventTypeKey,
    required String operationId,
    required String resultKey,
    String? sourcePath,
    String? destinationPath,
    String? expectedSha256,
    String? actualSha256,
    String? errorCode,
    String? messageSafe,
  }) async {
    await _db
        .into(_db.fileEvents)
        .insert(
          FileEventsCompanion.insert(
            documentId: Value(documentId),
            fileId: Value(fileId),
            eventTypeKey: eventTypeKey,
            operationId: operationId,
            sourcePath: Value(sourcePath),
            destinationPath: Value(destinationPath),
            expectedSha256: Value(expectedSha256),
            actualSha256: Value(actualSha256),
            resultKey: resultKey,
            errorCode: Value(errorCode),
            messageSafe: Value(messageSafe),
            createdAt: _clock.nowUtc().toIso8601String(),
          ),
        );
  }

  // ── Success persistence ────────────────────────────────────────────────────

  @override
  Future<int> persistManagedCopySuccess(ManagedCopyPersistenceData data) async {
    return _db.transaction(() async {
      final String ts = data.nowUtc.toIso8601String();

      // 0. Pre-write consistency checks — all run inside the transaction so
      //    any race between check and write is prevented by SQLite's
      //    serialized transaction isolation.
      final docRows = await (_db.select(
        _db.documents,
      )..where((d) => d.id.equals(data.documentId))).get();
      if (docRows.isEmpty) {
        throw StateError('Pre-write validation failed: document not found.');
      }
      final doc = docRows.first;
      if (doc.workflowStatusKey != WorkflowStatusKey.classified) {
        throw StateError(
          'Pre-write validation failed: workflow status is not classified.',
        );
      }
      if (doc.documentCode != data.documentCode) {
        throw StateError(
          'Pre-write validation failed: document code does not match.',
        );
      }
      final existingManaged =
          await (_db.select(_db.documentFiles)..where(
                (f) =>
                    f.documentId.equals(data.documentId) &
                    f.fileRoleKey.equals(FileRoleKey.managedCopy),
              ))
              .get();

      // Re-copy is allowed for a classified document even when a prior
      // managed_copy row is still healthy (P3.1-patch): a document edited
      // while copied_to_library, or returned from copied_to_library to
      // classified, can leave a stale healthy managed_copy record behind.
      // Mark every existing HEALTHY managed-copy row for this document as
      // 'missing' before persisting the fresh one, so re-copying never leaves
      // two rows both claiming to be the current healthy copy. Rows already
      // 'missing' or 'corrupted' are left untouched — those health states are
      // meaningful (M8.6/M11.4 reconciliation) and must not be collapsed into
      // a generic 'missing'.
      for (final row in existingManaged) {
        if (row.fileHealthKey == FileHealthKey.healthy) {
          await (_db.update(
            _db.documentFiles,
          )..where((f) => f.id.equals(row.id))).write(
            const DocumentFilesCompanion(
              fileHealthKey: Value(FileHealthKey.missing),
            ),
          );
        }
      }

      // Any pre-existing row at this exact managed path is now safe to
      // revive regardless of its original health: a healthy one was just
      // marked missing above, and a missing/corrupted one already qualifies.
      final matchingRevivableRows = existingManaged
          .where((r) => _samePath(r.absolutePath, data.managedFilePath))
          .toList(growable: false);
      if (matchingRevivableRows.length > 1) {
        throw StateError(
          'Pre-write validation failed: duplicate managed copy rows at the '
          'same path.',
        );
      }

      // 1. Insert a new managed_copy row, or revive the row already occupying
      // this exact managed path (just marked 'missing' above, or previously
      // missing/corrupted from M8.6/M11.4 reconciliation). Reviving avoids the
      // absolute_path UNIQUE collision on re-copy.
      final int managedFileId;
      if (matchingRevivableRows.isEmpty) {
        managedFileId = await _db
            .into(_db.documentFiles)
            .insert(
              DocumentFilesCompanion.insert(
                documentId: data.documentId,
                fileRoleKey: FileRoleKey.managedCopy,
                fileName: data.managedFileName,
                absolutePath: data.managedFilePath,
                extension: '.pdf',
                fileSizeBytes: data.fileSizeBytes,
                sha256Hash: Value(data.sha256Hash),
                fileHealthKey: const Value(FileHealthKey.healthy),
                isReadOnlySource: const Value(false),
                // is_preferred stays false; source preference is not displaced.
                isPreferred: const Value(false),
                importedAt: Value(ts),
                createdAt: ts,
                updatedAt: ts,
              ),
            );
      } else {
        final row = matchingRevivableRows.single;
        managedFileId = row.id;
        await (_db.update(
          _db.documentFiles,
        )..where((f) => f.id.equals(managedFileId))).write(
          DocumentFilesCompanion(
            fileName: Value(data.managedFileName),
            absolutePath: Value(data.managedFilePath),
            extension: const Value('.pdf'),
            fileSizeBytes: Value(data.fileSizeBytes),
            sha256Hash: Value(data.sha256Hash),
            fileHealthKey: const Value(FileHealthKey.healthy),
            isReadOnlySource: const Value(false),
            isPreferred: const Value(false),
            importedAt: Value(ts),
            updatedAt: Value(ts),
          ),
        );
      }

      // 2. Append copy_completed inside the transaction.
      await _db
          .into(_db.fileEvents)
          .insert(
            FileEventsCompanion.insert(
              documentId: Value(data.documentId),
              fileId: Value(managedFileId),
              eventTypeKey: 'copy_completed',
              operationId: data.operationId,
              sourcePath: Value(data.sourceFilePath),
              destinationPath: Value(data.managedFilePath),
              actualSha256: Value(data.sha256Hash),
              resultKey: 'succeeded',
              createdAt: ts,
            ),
          );

      // 3. Append copy_verified inside the transaction.
      await _db
          .into(_db.fileEvents)
          .insert(
            FileEventsCompanion.insert(
              documentId: Value(data.documentId),
              fileId: Value(managedFileId),
              eventTypeKey: 'copy_verified',
              operationId: data.operationId,
              destinationPath: Value(data.managedFilePath),
              actualSha256: Value(data.sha256Hash),
              resultKey: 'succeeded',
              createdAt: ts,
            ),
          );

      // 4. Update document workflow to copied_to_library.
      await (_db.update(
        _db.documents,
      )..where((d) => d.id.equals(data.documentId))).write(
        DocumentsCompanion(
          workflowStatusKey: const Value(WorkflowStatusKey.copiedToLibrary),
          copiedToLibraryAt: Value(ts),
          updatedAt: Value(ts),
        ),
      );

      await _db.updateDocumentFts(data.documentId);

      return managedFileId;
    });
  }

  // ── M8.6: Missing-file reconciliation ──────────────────────────────────────

  @override
  Future<List<ManagedFileRef>> loadManagedCopyFiles(int documentId) async {
    final rows =
        await (_db.select(_db.documentFiles)..where(
              (f) =>
                  f.documentId.equals(documentId) &
                  f.fileRoleKey.equals(FileRoleKey.managedCopy),
            ))
            .get();
    return rows
        .map(
          (r) => ManagedFileRef(
            fileId: r.id,
            documentId: r.documentId,
            absolutePath: r.absolutePath,
            fileHealthKey: r.fileHealthKey,
            fileSizeBytes: r.fileSizeBytes,
            sha256Hash: r.sha256Hash,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> markManagedFileMissing({
    required int fileId,
    required int documentId,
    required String operationId,
    required DateTime now,
  }) async {
    final String ts = now.toIso8601String();
    await (_db.update(
      _db.documentFiles,
    )..where((f) => f.id.equals(fileId))).write(
      DocumentFilesCompanion(
        fileHealthKey: const Value(FileHealthKey.missing),
        updatedAt: Value(ts),
      ),
    );
    await _db
        .into(_db.fileEvents)
        .insert(
          FileEventsCompanion.insert(
            documentId: Value(documentId),
            fileId: Value(fileId),
            eventTypeKey: 'marked_missing',
            operationId: operationId,
            resultKey: 'warning',
            createdAt: ts,
          ),
        );
  }

  @override
  Future<void> restoreManagedFileHealthy({
    required int fileId,
    required int documentId,
    required String operationId,
    required DateTime now,
  }) {
    final String ts = now.toIso8601String();
    return _db.transaction(() async {
      await (_db.update(_db.documentFiles)..where(
            (f) =>
                f.id.equals(fileId) &
                f.documentId.equals(documentId) &
                f.fileRoleKey.equals(FileRoleKey.managedCopy),
          ))
          .write(
            DocumentFilesCompanion(
              fileHealthKey: const Value(FileHealthKey.healthy),
              updatedAt: Value(ts),
            ),
          );

      await _db
          .into(_db.fileEvents)
          .insert(
            FileEventsCompanion.insert(
              documentId: Value(documentId),
              fileId: Value(fileId),
              eventTypeKey: 'existence_checked',
              operationId: operationId,
              resultKey: 'succeeded',
              messageSafe: const Value(
                'Missing managed copy verified and restored.',
              ),
              createdAt: ts,
            ),
          );

      await (_db.update(
        _db.documents,
      )..where((d) => d.id.equals(documentId))).write(
        DocumentsCompanion(
          workflowStatusKey: const Value(WorkflowStatusKey.copiedToLibrary),
          copiedToLibraryAt: Value(ts),
          updatedAt: Value(ts),
        ),
      );
    });
  }

  @override
  Future<void> downgradeDocumentToClassified({
    required int documentId,
    required DateTime now,
  }) async {
    final String ts = now.toIso8601String();
    await (_db.update(_db.documents)..where(
          (d) =>
              d.id.equals(documentId) &
              (d.workflowStatusKey.equals(WorkflowStatusKey.copiedToLibrary) |
                  d.workflowStatusKey.equals(WorkflowStatusKey.readyForExport)),
        ))
        .write(
          DocumentsCompanion(
            workflowStatusKey: const Value(WorkflowStatusKey.classified),
            updatedAt: Value(ts),
          ),
        );
  }

  // ── M11.4: Bulk managed-copy integrity reconciliation ─────────────────────

  @override
  Future<List<ManagedFileRef>> loadAllManagedCopyFiles() async {
    final rows = await (_db.select(
      _db.documentFiles,
    )..where((f) => f.fileRoleKey.equals(FileRoleKey.managedCopy))).get();
    return rows
        .map(
          (r) => ManagedFileRef(
            fileId: r.id,
            documentId: r.documentId,
            absolutePath: r.absolutePath,
            fileHealthKey: r.fileHealthKey,
            fileSizeBytes: r.fileSizeBytes,
            sha256Hash: r.sha256Hash,
          ),
        )
        .toList(growable: false);
  }

  @override
  Future<void> markManagedFileCorrupted({
    required int fileId,
    required int documentId,
    required String operationId,
    required DateTime now,
  }) async {
    final String ts = now.toIso8601String();
    await (_db.update(
      _db.documentFiles,
    )..where((f) => f.id.equals(fileId))).write(
      DocumentFilesCompanion(
        fileHealthKey: const Value(FileHealthKey.corrupted),
        updatedAt: Value(ts),
      ),
    );
    await _db
        .into(_db.fileEvents)
        .insert(
          FileEventsCompanion.insert(
            documentId: Value(documentId),
            fileId: Value(fileId),
            eventTypeKey: 'content_mismatch',
            operationId: operationId,
            resultKey: 'warning',
            createdAt: ts,
          ),
        );
  }

  @override
  Future<List<int>> loadCopiedToLibraryDocumentIds() async {
    final rows =
        await (_db.selectOnly(_db.documents)
              ..addColumns([_db.documents.id])
              ..where(
                _db.documents.workflowStatusKey.equals(
                  WorkflowStatusKey.copiedToLibrary,
                ),
              ))
            .get();
    return rows
        .map((row) => row.read(_db.documents.id)!)
        .toList(growable: false);
  }

  @override
  Future<List<({int documentId, String workflowStatusKey})>>
  loadDocumentsWithStaleDocumentCode() async {
    final codedDocRows =
        await (_db.selectOnly(_db.documents)
              ..addColumns([_db.documents.id, _db.documents.workflowStatusKey])
              ..where(_db.documents.documentCode.isNotNull()))
            .get();
    if (codedDocRows.isEmpty) return const [];

    final healthyRows =
        await (_db.selectOnly(_db.documentFiles)
              ..addColumns([_db.documentFiles.documentId])
              ..where(
                _db.documentFiles.fileRoleKey.equals(
                      FileRoleKey.managedCopy,
                    ) &
                    _db.documentFiles.fileHealthKey.equals(
                      FileHealthKey.healthy,
                    ),
              ))
            .get();
    final healthyDocIds = healthyRows
        .map((row) => row.read(_db.documentFiles.documentId)!)
        .toSet();

    return codedDocRows
        .map(
          (row) => (
            documentId: row.read(_db.documents.id)!,
            workflowStatusKey: row.read(_db.documents.workflowStatusKey)!,
          ),
        )
        .where((entry) => !healthyDocIds.contains(entry.documentId))
        .toList(growable: false);
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  Future<String?> _setting(String key) async {
    final row = await (_db.select(
      _db.settings,
    )..where((s) => s.key.equals(key))).getSingleOrNull();
    final value = row?.value;
    if (value == null || value.trim().isEmpty) return null;
    return value;
  }

  static bool _samePath(String a, String b) =>
      a.replaceAll('/', r'\').toLowerCase() ==
      b.replaceAll('/', r'\').toLowerCase();
}
