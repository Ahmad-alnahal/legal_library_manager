// lib/features/managed_copy/data/repositories/drift_managed_copy_repository.dart

import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../core/database/app_database.dart';
import '../../../../core/time/clock.dart';
import '../../domain/entities/copy_roots.dart';
import '../../domain/entities/document_copy_state.dart';
import '../../domain/entities/managed_copy_persistence_data.dart';
import '../../domain/entities/managed_file_ref.dart';
import '../../domain/entities/source_file_candidate.dart';
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
                  f.fileRoleKey.equals('managed_copy'),
            ))
            .get();

    return DocumentCopyState(
      documentId: doc.id,
      workflowStatusKey: doc.workflowStatusKey,
      existingDocumentCode: doc.documentCode,
      hasManagedCopy: managedCopyRows.isNotEmpty,
      hasHealthyManagedCopy: managedCopyRows.any(
        (r) => r.fileHealthKey != 'missing',
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
  Future<String> loadDatabaseRoot() async {
    final dir = await getApplicationSupportDirectory();
    return dir.path;
  }

  // ── Source file queries ────────────────────────────────────────────────────

  @override
  Future<List<String>> loadDocumentSourcePaths(int documentId) async {
    final rows =
        await (_db.select(_db.documentFiles)..where(
              (f) =>
                  f.documentId.equals(documentId) &
                  f.fileRoleKey.equals('source_original'),
            ))
            .get();
    return rows.map((r) => r.absolutePath).toList(growable: false);
  }

  @override
  Future<List<String>> loadAllSourcePaths() async {
    final rows = await (_db.select(
      _db.documentFiles,
    )..where((f) => f.fileRoleKey.equals('source_original'))).get();
    return rows.map((row) => row.absolutePath).toList(growable: false);
  }

  @override
  Future<List<SourceFileCandidate>> loadEligibleSources(int documentId) async {
    final rows =
        await (_db.select(_db.documentFiles)..where(
              (f) =>
                  f.documentId.equals(documentId) &
                  f.fileRoleKey.equals('source_original'),
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
            isPreferred: r.isPreferred,
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
      if (doc.workflowStatusKey != 'classified') {
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
                    f.fileRoleKey.equals('managed_copy'),
              ))
              .get();
      // Allow re-copy when all prior managed-copy rows are marked 'missing'
      // (M8.6 reconciliation). Block only when a healthy copy exists.
      final hasHealthyCopy = existingManaged.any(
        (r) => r.fileHealthKey != 'missing',
      );
      if (hasHealthyCopy) {
        throw StateError(
          'Pre-write validation failed: a healthy managed copy already exists.',
        );
      }

      final matchingMissingRows = existingManaged
          .where(
            (r) =>
                r.fileHealthKey == 'missing' &&
                _samePath(r.absolutePath, data.managedFilePath),
          )
          .toList(growable: false);
      if (matchingMissingRows.length > 1) {
        throw StateError(
          'Pre-write validation failed: duplicate missing managed copy rows.',
        );
      }

      // 1. Insert a new managed_copy row, or revive the existing missing row
      // for this exact managed path. Reviving avoids the absolute_path UNIQUE
      // collision after a user restores or re-copies a previously missing file.
      final int managedFileId;
      if (matchingMissingRows.isEmpty) {
        managedFileId = await _db
            .into(_db.documentFiles)
            .insert(
              DocumentFilesCompanion.insert(
                documentId: data.documentId,
                fileRoleKey: 'managed_copy',
                fileName: data.managedFileName,
                absolutePath: data.managedFilePath,
                extension: '.pdf',
                fileSizeBytes: data.fileSizeBytes,
                sha256Hash: Value(data.sha256Hash),
                fileHealthKey: const Value('healthy'),
                isReadOnlySource: const Value(false),
                // is_preferred stays false; source preference is not displaced.
                isPreferred: const Value(false),
                importedAt: Value(ts),
                createdAt: ts,
                updatedAt: ts,
              ),
            );
      } else {
        final row = matchingMissingRows.single;
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
            fileHealthKey: const Value('healthy'),
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
          workflowStatusKey: const Value('copied_to_library'),
          copiedToLibraryAt: Value(ts),
          updatedAt: Value(ts),
        ),
      );

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
                  f.fileRoleKey.equals('managed_copy'),
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
        fileHealthKey: const Value('missing'),
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
                f.fileRoleKey.equals('managed_copy'),
          ))
          .write(
            DocumentFilesCompanion(
              fileHealthKey: const Value('healthy'),
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
          workflowStatusKey: const Value('copied_to_library'),
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
              d.workflowStatusKey.equals('copied_to_library'),
        ))
        .write(
          DocumentsCompanion(
            workflowStatusKey: const Value('classified'),
            updatedAt: Value(ts),
          ),
        );
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
