// test/features/managed_copy/data/drift_managed_copy_reconciliation_test.dart
//
// Tests for M8.6 repository additions:
//  - loadManagedCopyFiles
//  - markManagedFileMissing
//  - downgradeDocumentToClassified
//  - persistManagedCopySuccess allows re-copy when all prior copies are missing
//  - loadDocumentState reflects hasHealthyManagedCopy correctly

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/constants/domain_keys.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/features/managed_copy/data/repositories/drift_managed_copy_repository.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/managed_copy_persistence_data.dart';

class _FakeClock extends Clock {
  _FakeClock([DateTime? t]) : _now = t ?? DateTime.utc(2026, 6, 17, 12, 0, 0);
  final DateTime _now;
  @override
  DateTime nowUtc() => _now;
}

const _kHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

Future<void> _seedReferenceData(AppDatabase db) async {
  for (final entry in [
    (WorkflowStatusKey.imported, 'مستورد', 'Imported'),
    (WorkflowStatusKey.inProgress, 'قيد التصنيف', 'In Progress'),
    (WorkflowStatusKey.classified, 'مصنف', 'Classified'),
    (WorkflowStatusKey.copiedToLibrary, 'منسوخ إلى المكتبة', 'Copied to Library'),
    (WorkflowStatusKey.readyForExport, 'جاهز للتصدير', 'Ready for Export'),
  ]) {
    await db
        .into(db.workflowStatuses)
        .insertOnConflictUpdate(
          WorkflowStatusesCompanion.insert(
            key: entry.$1,
            nameAr: entry.$2,
            nameEn: entry.$3,
            sortOrder: 1,
            isActive: true,
          ),
        );
  }
  for (final entry in [
    (FileRoleKey.sourceOriginal, 'المصدر الأصلي', 'Source Original'),
    (FileRoleKey.managedCopy, 'نسخة مدارة', 'Managed Copy'),
  ]) {
    await db
        .into(db.fileRoles)
        .insertOnConflictUpdate(
          FileRolesCompanion.insert(
            key: entry.$1,
            nameAr: entry.$2,
            nameEn: entry.$3,
            sortOrder: 1,
            isActive: true,
          ),
        );
  }
  for (final entry in [
    (FileHealthKey.unknown, 'غير معروف', 'Unknown'),
    (FileHealthKey.healthy, 'سليم', 'Healthy'),
    (FileHealthKey.corrupted, 'تالف', 'Corrupted'),
    (FileHealthKey.missing, 'مفقود', 'Missing'),
  ]) {
    await db
        .into(db.fileHealthStatuses)
        .insertOnConflictUpdate(
          FileHealthStatusesCompanion.insert(
            key: entry.$1,
            nameAr: entry.$2,
            nameEn: entry.$3,
            sortOrder: 1,
            isActive: true,
          ),
        );
  }
  for (final entry in [
    (TrustLevelKey.unverified, 'غير موثق', 'Unverified'),
  ]) {
    await db
        .into(db.trustLevels)
        .insertOnConflictUpdate(
          TrustLevelsCompanion.insert(
            key: entry.$1,
            nameAr: entry.$2,
            nameEn: entry.$3,
            sortOrder: 1,
            isActive: true,
          ),
        );
  }
  for (final entry in [
    (UsageRightsKey.unknown, 'غير معروف', 'Unknown'),
  ]) {
    await db
        .into(db.usageRights)
        .insertOnConflictUpdate(
          UsageRightsCompanion.insert(
            key: entry.$1,
            nameAr: entry.$2,
            nameEn: entry.$3,
            sortOrder: 1,
            isActive: true,
          ),
        );
  }
  for (final entry in [(MetadataQualityKey.low, 'منخفض', 'Low')]) {
    await db
        .into(db.metadataQualities)
        .insertOnConflictUpdate(
          MetadataQualitiesCompanion.insert(
            key: entry.$1,
            nameAr: entry.$2,
            nameEn: entry.$3,
            sortOrder: 1,
            isActive: true,
          ),
        );
  }
}

Future<int> _insertDocument(
  AppDatabase db, {
  String status = WorkflowStatusKey.classified,
  String? code,
}) => db
    .into(db.documents)
    .insert(
      DocumentsCompanion.insert(
        workflowStatusKey: Value(status),
        documentCode: Value(code),
        createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
        updatedAt: DateTime.utc(2026, 1, 1).toIso8601String(),
      ),
    );

Future<int> _insertManagedCopyFile(
  AppDatabase db,
  int documentId, {
  String path = r'C:\Library\files\DOC-0000001.pdf',
  String healthKey = FileHealthKey.healthy,
}) => db
    .into(db.documentFiles)
    .insert(
      DocumentFilesCompanion.insert(
        documentId: documentId,
        fileRoleKey: FileRoleKey.managedCopy,
        fileName: 'DOC-0000001.pdf',
        absolutePath: path,
        extension: '.pdf',
        fileSizeBytes: 2048,
        fileHealthKey: Value(healthKey),
        createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
        updatedAt: DateTime.utc(2026, 1, 1).toIso8601String(),
      ),
    );

Future<int> _insertSourceFile(AppDatabase db, int documentId) => db
    .into(db.documentFiles)
    .insert(
      DocumentFilesCompanion.insert(
        documentId: documentId,
        fileRoleKey: FileRoleKey.sourceOriginal,
        fileName: 'doc.pdf',
        absolutePath: r'C:\Sources\doc.pdf',
        extension: '.pdf',
        fileSizeBytes: 1024,
        sha256Hash: const Value(_kHash),
        fileHealthKey: const Value(FileHealthKey.healthy),
        isReadOnlySource: const Value(true),
        isPreferred: const Value(true),
        createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
        updatedAt: DateTime.utc(2026, 1, 1).toIso8601String(),
      ),
    );

void main() {
  late AppDatabase db;
  late DriftManagedCopyRepository repo;
  late _FakeClock clock;

  setUp(() async {
    db = AppDatabase.inMemory();
    clock = _FakeClock();
    repo = DriftManagedCopyRepository(db, clock);
    await _seedReferenceData(db);
  });

  tearDown(() => db.close());

  // ── loadManagedCopyFiles ───────────────────────────────────────────────────

  group('loadManagedCopyFiles', () {
    test('returns empty list when no managed-copy files exist', () async {
      final docId = await _insertDocument(db);
      final refs = await repo.loadManagedCopyFiles(docId);
      expect(refs, isEmpty);
    });

    test('returns all managed-copy rows regardless of health', () async {
      final docId = await _insertDocument(db, status: WorkflowStatusKey.copiedToLibrary);
      await _insertManagedCopyFile(db, docId, healthKey: FileHealthKey.healthy);
      await _insertManagedCopyFile(
        db,
        docId,
        path: r'C:\Library\files\DOC-0000001-old.pdf',
        healthKey: FileHealthKey.missing,
      );
      final refs = await repo.loadManagedCopyFiles(docId);
      expect(refs.length, 2);
      expect(refs.map((r) => r.fileHealthKey).toSet(), {
        FileHealthKey.healthy,
        FileHealthKey.missing,
      });
    });

    test('maps fields correctly', () async {
      final docId = await _insertDocument(db, status: WorkflowStatusKey.copiedToLibrary);
      final fileId = await _insertManagedCopyFile(db, docId);
      final refs = await repo.loadManagedCopyFiles(docId);
      expect(refs.length, 1);
      final ref = refs.first;
      expect(ref.fileId, fileId);
      expect(ref.documentId, docId);
      expect(ref.absolutePath, r'C:\Library\files\DOC-0000001.pdf');
      expect(ref.fileHealthKey, FileHealthKey.healthy);
    });
  });

  // ── markManagedFileMissing ─────────────────────────────────────────────────

  group('markManagedFileMissing', () {
    test('updates file_health_key to missing', () async {
      final docId = await _insertDocument(db, status: WorkflowStatusKey.copiedToLibrary);
      final fileId = await _insertManagedCopyFile(db, docId);
      final now = DateTime.utc(2026, 6, 17, 12, 0, 0);

      await repo.markManagedFileMissing(
        fileId: fileId,
        documentId: docId,
        operationId: 'op_test_1',
        now: now,
      );

      final row = await (db.select(
        db.documentFiles,
      )..where((f) => f.id.equals(fileId))).getSingle();
      expect(row.fileHealthKey, FileHealthKey.missing);
      expect(row.updatedAt, now.toIso8601String());
    });

    test('appends a marked_missing file_event', () async {
      final docId = await _insertDocument(db, status: WorkflowStatusKey.copiedToLibrary);
      final fileId = await _insertManagedCopyFile(db, docId);
      final now = DateTime.utc(2026, 6, 17, 12, 0, 0);

      await repo.markManagedFileMissing(
        fileId: fileId,
        documentId: docId,
        operationId: 'op_test_1',
        now: now,
      );

      final events = await (db.select(
        db.fileEvents,
      )..where((e) => e.fileId.equals(fileId))).get();
      expect(events.length, 1);
      expect(events.first.eventTypeKey, 'marked_missing');
      expect(events.first.resultKey, 'warning');
      expect(events.first.operationId, 'op_test_1');
    });

    test('does not affect other files', () async {
      final docId = await _insertDocument(db, status: WorkflowStatusKey.copiedToLibrary);
      final fileId1 = await _insertManagedCopyFile(db, docId);
      final fileId2 = await _insertManagedCopyFile(
        db,
        docId,
        path: r'C:\Library\files\DOC-0000001-v2.pdf',
      );
      final now = DateTime.utc(2026, 6, 17, 12, 0, 0);

      await repo.markManagedFileMissing(
        fileId: fileId1,
        documentId: docId,
        operationId: 'op_test_1',
        now: now,
      );

      final row2 = await (db.select(
        db.documentFiles,
      )..where((f) => f.id.equals(fileId2))).getSingle();
      expect(row2.fileHealthKey, FileHealthKey.healthy);
    });
  });

  // ── downgradeDocumentToClassified ─────────────────────────────────────────

  group('restoreManagedFileHealthy', () {
    test(
      'updates file row, workflow, and appends allowed audit event',
      () async {
        final docId = await _insertDocument(db, status: WorkflowStatusKey.classified);
        final fileId = await _insertManagedCopyFile(
          db,
          docId,
          healthKey: FileHealthKey.missing,
        );
        final now = DateTime.utc(2026, 6, 18, 13, 0, 0);

        await repo.restoreManagedFileHealthy(
          fileId: fileId,
          documentId: docId,
          operationId: 'op_restore_1',
          now: now,
        );

        final file = await (db.select(
          db.documentFiles,
        )..where((f) => f.id.equals(fileId))).getSingle();
        expect(file.fileHealthKey, FileHealthKey.healthy);
        expect(file.updatedAt, now.toIso8601String());

        final doc = await (db.select(
          db.documents,
        )..where((d) => d.id.equals(docId))).getSingle();
        expect(doc.workflowStatusKey, WorkflowStatusKey.copiedToLibrary);
        expect(doc.copiedToLibraryAt, now.toIso8601String());

        final event = await (db.select(
          db.fileEvents,
        )..where((e) => e.fileId.equals(fileId))).getSingle();
        expect(event.eventTypeKey, 'existence_checked');
        expect(event.resultKey, 'succeeded');
        expect(
          event.messageSafe,
          'Missing managed copy verified and restored.',
        );
      },
    );
  });

  group('downgradeDocumentToClassified', () {
    test(
      'changes workflow_status_key from copied_to_library to classified',
      () async {
        final docId = await _insertDocument(db, status: WorkflowStatusKey.copiedToLibrary);
        final now = DateTime.utc(2026, 6, 17, 12, 0, 0);

        await repo.downgradeDocumentToClassified(documentId: docId, now: now);

        final doc = await (db.select(
          db.documents,
        )..where((d) => d.id.equals(docId))).getSingle();
        expect(doc.workflowStatusKey, WorkflowStatusKey.classified);
        expect(doc.updatedAt, now.toIso8601String());
      },
    );

    test('changes workflow_status_key from ready_for_export to classified '
        '(QA follow-up: stale document_code)', () async {
      final docId = await _insertDocument(db, status: WorkflowStatusKey.readyForExport);
      final now = DateTime.utc(2026, 6, 17, 12, 0, 0);

      await repo.downgradeDocumentToClassified(documentId: docId, now: now);

      final doc = await (db.select(
        db.documents,
      )..where((d) => d.id.equals(docId))).getSingle();
      expect(doc.workflowStatusKey, WorkflowStatusKey.classified);
      expect(doc.updatedAt, now.toIso8601String());
    });

    test('is idempotent when document is already classified', () async {
      final docId = await _insertDocument(db, status: WorkflowStatusKey.classified);
      final now = DateTime.utc(2026, 6, 17, 12, 0, 0);

      await expectLater(
        repo.downgradeDocumentToClassified(documentId: docId, now: now),
        completes,
      );

      final doc = await (db.select(
        db.documents,
      )..where((d) => d.id.equals(docId))).getSingle();
      expect(doc.workflowStatusKey, WorkflowStatusKey.classified);
    });

    test('does not touch documents in other workflow states', () async {
      final docId = await _insertDocument(db, status: WorkflowStatusKey.imported);
      final now = DateTime.utc(2026, 6, 17, 12, 0, 0);

      await repo.downgradeDocumentToClassified(documentId: docId, now: now);

      final doc = await (db.select(
        db.documents,
      )..where((d) => d.id.equals(docId))).getSingle();
      // WHERE clause filters on 'copied_to_library' only; imported stays.
      expect(doc.workflowStatusKey, WorkflowStatusKey.imported);
    });
  });

  // ── loadDocumentState — hasHealthyManagedCopy ──────────────────────────────

  group('loadDocumentState hasHealthyManagedCopy', () {
    test('is false when no managed-copy files exist', () async {
      final docId = await _insertDocument(db);
      final state = await repo.loadDocumentState(docId);
      expect(state!.hasManagedCopy, isFalse);
      expect(state.hasHealthyManagedCopy, isFalse);
    });

    test('is true when a healthy managed-copy exists', () async {
      final docId = await _insertDocument(db, status: WorkflowStatusKey.copiedToLibrary);
      await _insertManagedCopyFile(db, docId, healthKey: FileHealthKey.healthy);
      final state = await repo.loadDocumentState(docId);
      expect(state!.hasManagedCopy, isTrue);
      expect(state.hasHealthyManagedCopy, isTrue);
    });

    test('is false when all managed-copy files are marked missing', () async {
      final docId = await _insertDocument(db, status: WorkflowStatusKey.classified);
      await _insertManagedCopyFile(db, docId, healthKey: FileHealthKey.missing);
      final state = await repo.loadDocumentState(docId);
      // hasManagedCopy is still true (row exists), but no healthy copy.
      expect(state!.hasManagedCopy, isTrue);
      expect(state.hasHealthyManagedCopy, isFalse);
    });

    test('is false when the only managed-copy file is marked corrupted '
        '(bug 4 follow-up)', () async {
      final docId = await _insertDocument(db, status: WorkflowStatusKey.classified);
      await _insertManagedCopyFile(db, docId, healthKey: FileHealthKey.corrupted);
      final state = await repo.loadDocumentState(docId);
      expect(state!.hasManagedCopy, isTrue);
      expect(state.hasHealthyManagedCopy, isFalse);
    });

    test(
      'is true when at least one non-missing managed copy exists among multiple',
      () async {
        final docId = await _insertDocument(db, status: WorkflowStatusKey.copiedToLibrary);
        await _insertManagedCopyFile(db, docId, healthKey: FileHealthKey.missing);
        await _insertManagedCopyFile(
          db,
          docId,
          path: r'C:\Library\files\DOC-0000001-new.pdf',
          healthKey: FileHealthKey.healthy,
        );
        final state = await repo.loadDocumentState(docId);
        expect(state!.hasHealthyManagedCopy, isTrue);
      },
    );
  });

  // ── persistManagedCopySuccess — re-copy when all prior copies missing ──────

  group('persistManagedCopySuccess re-copy after reconciliation', () {
    test(
      'revives matching missing row instead of inserting duplicate absolute path',
      () async {
        final docId = await _insertDocument(
          db,
          status: WorkflowStatusKey.classified,
          code: 'DOC-0000001',
        );
        final srcId = await _insertSourceFile(db, docId);
        final missingId = await _insertManagedCopyFile(
          db,
          docId,
          healthKey: FileHealthKey.missing,
        );

        final now = DateTime.utc(2026, 6, 17, 12, 0, 0);
        final restoredId = await repo.persistManagedCopySuccess(
          ManagedCopyPersistenceData(
            documentId: docId,
            documentCode: 'DOC-0000001',
            operationId: 'op_restore_same_path',
            managedFilePath: r'C:\Library\files\DOC-0000001.pdf',
            managedFileName: 'DOC-0000001.pdf',
            sha256Hash: _kHash,
            fileSizeBytes: 2048,
            sourceFileId: srcId,
            sourceFilePath: r'C:\Sources\doc.pdf',
            nowUtc: now,
          ),
        );

        expect(restoredId, missingId);

        final managedRows =
            await (db.select(db.documentFiles)..where(
                  (f) =>
                      f.documentId.equals(docId) &
                      f.fileRoleKey.equals(FileRoleKey.managedCopy),
                ))
                .get();
        expect(managedRows, hasLength(1));
        expect(managedRows.single.id, missingId);
        expect(managedRows.single.fileHealthKey, FileHealthKey.healthy);
        expect(managedRows.single.sha256Hash, _kHash);

        final doc = await (db.select(
          db.documents,
        )..where((d) => d.id.equals(docId))).getSingle();
        expect(doc.workflowStatusKey, WorkflowStatusKey.copiedToLibrary);

        final eventTypes =
            (await (db.select(
                  db.fileEvents,
                )..where((e) => e.fileId.equals(missingId))).get())
                .map((event) => event.eventTypeKey)
                .toSet();
        expect(eventTypes, contains('copy_completed'));
        expect(eventTypes, contains('copy_verified'));
      },
    );

    test(
      'allows re-copy when the only prior managed-copy is marked missing',
      () async {
        final docId = await _insertDocument(
          db,
          status: WorkflowStatusKey.classified,
          code: 'DOC-0000001',
        );
        final srcId = await _insertSourceFile(db, docId);
        // Simulate a prior missing managed copy.
        await _insertManagedCopyFile(db, docId, healthKey: FileHealthKey.missing);

        final now = DateTime.utc(2026, 6, 17, 12, 0, 0);
        final newId = await repo.persistManagedCopySuccess(
          ManagedCopyPersistenceData(
            documentId: docId,
            documentCode: 'DOC-0000001',
            operationId: 'op_recopy_1',
            managedFilePath: r'C:\Library\files\DOC-0000001-new.pdf',
            managedFileName: 'DOC-0000001-new.pdf',
            sha256Hash: _kHash,
            fileSizeBytes: 2048,
            sourceFileId: srcId,
            sourceFilePath: r'C:\Sources\doc.pdf',
            nowUtc: now,
          ),
        );

        expect(newId, isPositive);
        final doc = await (db.select(
          db.documents,
        )..where((d) => d.id.equals(docId))).getSingle();
        expect(doc.workflowStatusKey, WorkflowStatusKey.copiedToLibrary);

        // The old missing row is preserved.
        final allFiles =
            await (db.select(db.documentFiles)..where(
                  (f) =>
                      f.documentId.equals(docId) &
                      f.fileRoleKey.equals(FileRoleKey.managedCopy),
                ))
                .get();
        expect(allFiles.length, 2);
        expect(
          allFiles.any((f) => f.fileHealthKey == FileHealthKey.missing),
          isTrue,
          reason: 'Old missing row must be preserved',
        );
        expect(
          allFiles.any((f) => f.fileHealthKey == FileHealthKey.healthy),
          isTrue,
          reason: 'New healthy row must be inserted',
        );
      },
    );

    test('revives matching corrupted row instead of inserting duplicate '
        'absolute path (bug 4 follow-up)', () async {
      final docId = await _insertDocument(
        db,
        status: WorkflowStatusKey.classified,
        code: 'DOC-0000001',
      );
      final srcId = await _insertSourceFile(db, docId);
      final corruptedId = await _insertManagedCopyFile(
        db,
        docId,
        healthKey: FileHealthKey.corrupted,
      );

      final now = DateTime.utc(2026, 6, 17, 12, 0, 0);
      final revivedId = await repo.persistManagedCopySuccess(
        ManagedCopyPersistenceData(
          documentId: docId,
          documentCode: 'DOC-0000001',
          operationId: 'op_revive_corrupted',
          managedFilePath: r'C:\Library\files\DOC-0000001.pdf',
          managedFileName: 'DOC-0000001.pdf',
          sha256Hash: _kHash,
          fileSizeBytes: 2048,
          sourceFileId: srcId,
          sourceFilePath: r'C:\Sources\doc.pdf',
          nowUtc: now,
        ),
      );

      expect(revivedId, corruptedId);

      final managedRows =
          await (db.select(db.documentFiles)..where(
                (f) =>
                    f.documentId.equals(docId) &
                    f.fileRoleKey.equals(FileRoleKey.managedCopy),
              ))
              .get();
      expect(managedRows, hasLength(1));
      expect(managedRows.single.id, corruptedId);
      expect(managedRows.single.fileHealthKey, FileHealthKey.healthy);
      expect(managedRows.single.sha256Hash, _kHash);

      final doc = await (db.select(
        db.documents,
      )..where((d) => d.id.equals(docId))).getSingle();
      expect(doc.workflowStatusKey, WorkflowStatusKey.copiedToLibrary);
    });

    test('allows re-copy when the only prior managed-copy is marked corrupted '
        '(bug 4 follow-up)', () async {
      final docId = await _insertDocument(
        db,
        status: WorkflowStatusKey.classified,
        code: 'DOC-0000001',
      );
      final srcId = await _insertSourceFile(db, docId);
      await _insertManagedCopyFile(db, docId, healthKey: FileHealthKey.corrupted);

      final now = DateTime.utc(2026, 6, 17, 12, 0, 0);
      final newId = await repo.persistManagedCopySuccess(
        ManagedCopyPersistenceData(
          documentId: docId,
          documentCode: 'DOC-0000001',
          operationId: 'op_recopy_corrupted',
          managedFilePath: r'C:\Library\files\DOC-0000001-new.pdf',
          managedFileName: 'DOC-0000001-new.pdf',
          sha256Hash: _kHash,
          fileSizeBytes: 2048,
          sourceFileId: srcId,
          sourceFilePath: r'C:\Sources\doc.pdf',
          nowUtc: now,
        ),
      );

      expect(newId, isPositive);
      final doc = await (db.select(
        db.documents,
      )..where((d) => d.id.equals(docId))).getSingle();
      expect(doc.workflowStatusKey, WorkflowStatusKey.copiedToLibrary);

      // The old corrupted row is preserved, not deleted.
      final allFiles =
          await (db.select(db.documentFiles)..where(
                (f) =>
                    f.documentId.equals(docId) &
                    f.fileRoleKey.equals(FileRoleKey.managedCopy),
              ))
              .get();
      expect(allFiles.length, 2);
      expect(
        allFiles.any((f) => f.fileHealthKey == FileHealthKey.corrupted),
        isTrue,
        reason: 'Old corrupted row must be preserved',
      );
      expect(
        allFiles.any((f) => f.fileHealthKey == FileHealthKey.healthy),
        isTrue,
        reason: 'New healthy row must be inserted',
      );
    });

    test('marks a pre-existing healthy managed-copy missing and allows re-copy '
        '(P3.1-patch: classified documents may re-copy over a stale healthy '
        'record)', () async {
      final docId = await _insertDocument(
        db,
        status: WorkflowStatusKey.classified,
        code: 'DOC-0000001',
      );
      final srcId = await _insertSourceFile(db, docId);
      // A healthy managed copy already exists.
      final staleId = await _insertManagedCopyFile(
        db,
        docId,
        healthKey: FileHealthKey.healthy,
      );

      final now = DateTime.utc(2026, 6, 17, 12, 0, 0);
      final newId = await repo.persistManagedCopySuccess(
        ManagedCopyPersistenceData(
          documentId: docId,
          documentCode: 'DOC-0000001',
          operationId: 'op_recopy',
          managedFilePath: r'C:\Library\files\DOC-0000001-dup.pdf',
          managedFileName: 'DOC-0000001-dup.pdf',
          sha256Hash: _kHash,
          fileSizeBytes: 2048,
          sourceFileId: srcId,
          sourceFilePath: r'C:\Sources\doc.pdf',
          nowUtc: now,
        ),
      );

      expect(newId, isNot(staleId));
      final staleRow = await (db.select(
        db.documentFiles,
      )..where((f) => f.id.equals(staleId))).getSingle();
      expect(staleRow.fileHealthKey, FileHealthKey.missing);
      final newRow = await (db.select(
        db.documentFiles,
      )..where((f) => f.id.equals(newId))).getSingle();
      expect(newRow.fileHealthKey, FileHealthKey.healthy);
    });
  });
}
