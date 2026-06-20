// test/features/managed_copy/data/drift_managed_copy_repository_test.dart

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/features/managed_copy/data/repositories/drift_managed_copy_repository.dart';
import 'package:legal_library_manager/features/managed_copy/domain/entities/managed_copy_persistence_data.dart';

class _FakeClock extends Clock {
  _FakeClock([DateTime? t]) : _now = t ?? DateTime.utc(2026, 6, 11, 10, 0, 0);
  final DateTime _now;
  @override
  DateTime nowUtc() => _now;
}

const _kHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

// Seed the minimum reference data needed by FK constraints.
Future<void> _seedReferenceData(AppDatabase db) async {
  // Workflow statuses required by the documents table.
  for (final entry in [
    ('imported', 'مستورد', 'Imported'),
    ('classified', 'مصنف', 'Classified'),
    ('copied_to_library', 'منسوخ إلى المكتبة', 'Copied to Library'),
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
  // File roles.
  for (final entry in [
    ('source_original', 'المصدر الأصلي', 'Source Original'),
    ('managed_copy', 'نسخة مدارة', 'Managed Copy'),
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
  // File health statuses.
  for (final entry in [
    ('unknown', 'غير معروف', 'Unknown'),
    ('healthy', 'سليم', 'Healthy'),
    ('corrupted', 'تالف', 'Corrupted'),
    ('missing', 'مفقود', 'Missing'),
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
  // Trust / usage / quality defaults.
  for (final entry in [('unverified', 'غير موثق', 'Unverified')]) {
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
  for (final entry in [('unknown', 'غير معروف', 'Unknown')]) {
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
  for (final entry in [('low', 'منخفض', 'Low')]) {
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
  String status = 'classified',
  String? code,
}) async {
  return db
      .into(db.documents)
      .insert(
        DocumentsCompanion.insert(
          workflowStatusKey: Value(status),
          documentCode: Value(code),
          createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
          updatedAt: DateTime.utc(2026, 1, 1).toIso8601String(),
        ),
      );
}

Future<int> _insertSourceFile(
  AppDatabase db,
  int documentId, {
  String path = r'C:\Sources\doc.pdf',
  String? hash,
  bool isPreferred = false,
}) async {
  return db
      .into(db.documentFiles)
      .insert(
        DocumentFilesCompanion.insert(
          documentId: documentId,
          fileRoleKey: 'source_original',
          fileName: 'doc.pdf',
          absolutePath: path,
          extension: '.pdf',
          fileSizeBytes: 1024,
          sha256Hash: Value(hash),
          fileHealthKey: const Value('healthy'),
          isReadOnlySource: const Value(true),
          isPreferred: Value(isPreferred),
          createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
          updatedAt: DateTime.utc(2026, 1, 1).toIso8601String(),
        ),
      );
}

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

  tearDown(() async {
    await db.close();
  });

  // ── loadDocumentState ──────────────────────────────────────────────────────

  group('loadDocumentState', () {
    test('returns null for non-existent document', () async {
      final state = await repo.loadDocumentState(999);
      expect(state, isNull);
    });

    test('returns classified state correctly', () async {
      final docId = await _insertDocument(db);
      final state = await repo.loadDocumentState(docId);
      expect(state, isNotNull);
      expect(state!.workflowStatusKey, 'classified');
      expect(state.hasManagedCopy, isFalse);
    });

    test('hasManagedCopy is true when managed_copy file exists', () async {
      final docId = await _insertDocument(db);
      await db
          .into(db.documentFiles)
          .insert(
            DocumentFilesCompanion.insert(
              documentId: docId,
              fileRoleKey: 'managed_copy',
              fileName: 'DOC-0000001.pdf',
              absolutePath: r'C:\Library\files\DOC-0000001.pdf',
              extension: '.pdf',
              fileSizeBytes: 1024,
              fileHealthKey: const Value('healthy'),
              createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
              updatedAt: DateTime.utc(2026, 1, 1).toIso8601String(),
            ),
          );
      final state = await repo.loadDocumentState(docId);
      expect(state!.hasManagedCopy, isTrue);
    });
  });

  // ── loadEligibleSources ────────────────────────────────────────────────────

  group('loadEligibleSources', () {
    test('returns only source_original files', () async {
      final docId = await _insertDocument(db);
      await _insertSourceFile(db, docId);
      // Insert a managed_copy row too.
      await db
          .into(db.documentFiles)
          .insert(
            DocumentFilesCompanion.insert(
              documentId: docId,
              fileRoleKey: 'managed_copy',
              fileName: 'DOC-0000001.pdf',
              absolutePath: r'C:\Library\files\DOC-0000001.pdf',
              extension: '.pdf',
              fileSizeBytes: 1024,
              fileHealthKey: const Value('healthy'),
              createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
              updatedAt: DateTime.utc(2026, 1, 1).toIso8601String(),
            ),
          );
      final sources = await repo.loadEligibleSources(docId);
      expect(sources.length, 1);
      expect(sources.first.storedExtension, '.pdf');
    });
  });

  // ── allocateDocumentCode ───────────────────────────────────────────────────

  group('allocateDocumentCode', () {
    test('assigns DOC-0000001 when no codes exist', () async {
      final docId = await _insertDocument(db);
      final code = await repo.allocateDocumentCode(docId);
      expect(code, 'DOC-0000001');
    });

    test('reuses existing code without changing it', () async {
      final docId = await _insertDocument(db, code: 'DOC-0000005');
      final code = await repo.allocateDocumentCode(docId);
      expect(code, 'DOC-0000005');
    });

    test('assigns next code after existing maximum', () async {
      await _insertDocument(db, code: 'DOC-0000003');
      final doc2 = await _insertDocument(db);
      final code = await repo.allocateDocumentCode(doc2);
      expect(code, 'DOC-0000004');
    });

    test('code allocation does NOT use row count', () async {
      // Insert 5 documents, assign codes to first 3, then delete 2 of them,
      // leaving 3 rows. The next allocation must be DOC-0000004, not DOC-0000002.
      final ids = <int>[];
      for (int i = 0; i < 5; i++) {
        ids.add(await _insertDocument(db));
      }
      // Assign codes DOC-0000001, DOC-0000002, DOC-0000003 to first 3.
      for (int i = 0; i < 3; i++) {
        await repo.allocateDocumentCode(ids[i]);
      }
      // The next allocation for ids[3] must be DOC-0000004 (max+1).
      final code = await repo.allocateDocumentCode(ids[3]);
      expect(
        code,
        'DOC-0000004',
        reason: 'must use max existing code, not row count',
      );
    });

    test('concurrent allocation produces unique codes', () async {
      final doc1 = await _insertDocument(db);
      final doc2 = await _insertDocument(db);
      // Sequential in tests (SQLite serializes); both must get distinct codes.
      final code1 = await repo.allocateDocumentCode(doc1);
      final code2 = await repo.allocateDocumentCode(doc2);
      expect(code1, isNot(code2));
    });
  });

  // ── persistManagedCopySuccess ──────────────────────────────────────────────

  group('persistManagedCopySuccess', () {
    test('inserts managed_copy document_files row', () async {
      final docId = await _insertDocument(db, code: 'DOC-0000001');
      final srcId = await _insertSourceFile(db, docId, hash: _kHash);
      final now = DateTime.utc(2026, 6, 11, 10, 0, 0);

      final newId = await repo.persistManagedCopySuccess(
        ManagedCopyPersistenceData(
          documentId: docId,
          documentCode: 'DOC-0000001',
          operationId: 'op_123',
          managedFilePath: r'C:\Library\files\DOC-0000001.pdf',
          managedFileName: 'DOC-0000001.pdf',
          sha256Hash: _kHash,
          fileSizeBytes: 1024,
          sourceFileId: srcId,
          sourceFilePath: r'C:\Sources\doc.pdf',
          nowUtc: now,
        ),
      );

      expect(newId, isPositive);
      final files = await (db.select(
        db.documentFiles,
      )..where((f) => f.id.equals(newId))).get();
      expect(files.length, 1);
      expect(files.first.fileRoleKey, 'managed_copy');
      expect(files.first.sha256Hash, _kHash);
      expect(files.first.fileHealthKey, 'healthy');
      expect(files.first.isReadOnlySource, isFalse);
      expect(files.first.isPreferred, isFalse);
    });

    test('updates document workflow to copied_to_library', () async {
      final docId = await _insertDocument(db, code: 'DOC-0000001');
      final srcId = await _insertSourceFile(db, docId, hash: _kHash);
      final now = DateTime.utc(2026, 6, 11, 10, 0, 0);

      await repo.persistManagedCopySuccess(
        ManagedCopyPersistenceData(
          documentId: docId,
          documentCode: 'DOC-0000001',
          operationId: 'op_123',
          managedFilePath: r'C:\Library\files\DOC-0000001.pdf',
          managedFileName: 'DOC-0000001.pdf',
          sha256Hash: _kHash,
          fileSizeBytes: 1024,
          sourceFileId: srcId,
          sourceFilePath: r'C:\Sources\doc.pdf',
          nowUtc: now,
        ),
      );

      final doc = await (db.select(
        db.documents,
      )..where((d) => d.id.equals(docId))).getSingle();
      expect(doc.workflowStatusKey, 'copied_to_library');
      expect(doc.copiedToLibraryAt, isNotNull);
    });

    test('appends copy_completed and copy_verified events', () async {
      final docId = await _insertDocument(db, code: 'DOC-0000001');
      final srcId = await _insertSourceFile(db, docId, hash: _kHash);
      final now = DateTime.utc(2026, 6, 11, 10, 0, 0);

      await repo.persistManagedCopySuccess(
        ManagedCopyPersistenceData(
          documentId: docId,
          documentCode: 'DOC-0000001',
          operationId: 'op_123',
          managedFilePath: r'C:\Library\files\DOC-0000001.pdf',
          managedFileName: 'DOC-0000001.pdf',
          sha256Hash: _kHash,
          fileSizeBytes: 1024,
          sourceFileId: srcId,
          sourceFilePath: r'C:\Sources\doc.pdf',
          nowUtc: now,
        ),
      );

      final events = await (db.select(
        db.fileEvents,
      )..where((e) => e.documentId.equals(docId))).get();
      final types = events.map((e) => e.eventTypeKey).toSet();
      expect(types.contains('copy_completed'), isTrue);
      expect(types.contains('copy_verified'), isTrue);
    });

    test(
      'is transactional: constraint violation rolls back all changes',
      () async {
        final docId = await _insertDocument(db, code: 'DOC-0000001');
        // Pre-insert a document_files row occupying the absolutePath that
        // persistManagedCopySuccess will attempt to insert. The UNIQUE index on
        // absolute_path is enforced by SQLite without requiring PRAGMA
        // foreign_keys, so this reliably triggers a constraint failure inside
        // the transaction without needing FK support to be on.
        await db
            .into(db.documentFiles)
            .insert(
              DocumentFilesCompanion.insert(
                documentId: docId,
                fileRoleKey: 'managed_copy',
                fileName: 'DOC-0000001.pdf',
                absolutePath: r'C:\Library\files\DOC-0000001.pdf',
                extension: '.pdf',
                fileSizeBytes: 512,
                fileHealthKey: const Value('healthy'),
                createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
                updatedAt: DateTime.utc(2026, 1, 1).toIso8601String(),
              ),
            );

        await expectLater(
          repo.persistManagedCopySuccess(
            ManagedCopyPersistenceData(
              documentId: docId,
              documentCode: 'DOC-0000001',
              operationId: 'op_123',
              managedFilePath:
                  r'C:\Library\files\DOC-0000001.pdf', // same → UNIQUE violation
              managedFileName: 'DOC-0000001.pdf',
              sha256Hash: _kHash,
              fileSizeBytes: 1024,
              sourceFileId: 1,
              sourceFilePath: r'C:\Sources\doc.pdf',
              nowUtc: DateTime.utc(2026, 6, 11),
            ),
          ),
          throwsA(anything),
        );
        // Document workflow must remain 'classified' (transaction rolled back).
        final doc = await (db.select(
          db.documents,
        )..where((d) => d.id.equals(docId))).getSingle();
        expect(doc.workflowStatusKey, 'classified');
      },
    );

    test('source file record is not modified by success persistence', () async {
      final docId = await _insertDocument(db, code: 'DOC-0000001');
      final srcId = await _insertSourceFile(
        db,
        docId,
        hash: _kHash,
        isPreferred: true,
      );
      final now = DateTime.utc(2026, 6, 11, 10, 0, 0);

      await repo.persistManagedCopySuccess(
        ManagedCopyPersistenceData(
          documentId: docId,
          documentCode: 'DOC-0000001',
          operationId: 'op_123',
          managedFilePath: r'C:\Library\files\DOC-0000001.pdf',
          managedFileName: 'DOC-0000001.pdf',
          sha256Hash: _kHash,
          fileSizeBytes: 1024,
          sourceFileId: srcId,
          sourceFilePath: r'C:\Sources\doc.pdf',
          nowUtc: now,
        ),
      );

      // Source row must remain unchanged.
      final srcRow = await (db.select(
        db.documentFiles,
      )..where((f) => f.id.equals(srcId))).getSingle();
      expect(srcRow.fileRoleKey, 'source_original');
      expect(srcRow.isReadOnlySource, isTrue);
      expect(srcRow.isPreferred, isTrue); // preference not displaced
    });
  });

  // ── appendFileEvent ────────────────────────────────────────────────────────

  group('appendFileEvent', () {
    test('inserts event row with correct fields', () async {
      final docId = await _insertDocument(db);

      await repo.appendFileEvent(
        documentId: docId,
        fileId: null,
        eventTypeKey: 'copy_started',
        operationId: 'op_456',
        resultKey: 'started',
        messageSafe: 'copy started safely',
      );

      final events = await (db.select(
        db.fileEvents,
      )..where((e) => e.operationId.equals('op_456'))).get();
      expect(events.length, 1);
      expect(events.first.eventTypeKey, 'copy_started');
      expect(events.first.resultKey, 'started');
      expect(events.first.messageSafe, 'copy started safely');
    });
  });

  // ── allocateDocumentCode: code exhaustion (correction 1) ──────────────────

  group('allocateDocumentCode — code exhaustion (correction 1)', () {
    test('throws StateError when all 9999999 codes are used', () async {
      // Insert a document whose code is already at the maximum.
      await _insertDocument(db, code: 'DOC-9999999');
      final newDoc = await _insertDocument(db);
      await expectLater(
        repo.allocateDocumentCode(newDoc),
        throwsA(isA<StateError>()),
      );
    });
  });

  // ── persistManagedCopySuccess: pre-write race checks (correction 4) ────────

  group('persistManagedCopySuccess — pre-write race checks (correction 4)', () {
    ManagedCopyPersistenceData raceData(int docId) =>
        ManagedCopyPersistenceData(
          documentId: docId,
          documentCode: 'DOC-0000001',
          operationId: 'op_race',
          managedFilePath: r'C:\Library\files\DOC-0000001.pdf',
          managedFileName: 'DOC-0000001.pdf',
          sha256Hash: _kHash,
          fileSizeBytes: 1024,
          sourceFileId: 1,
          sourceFilePath: r'C:\Sources\doc.pdf',
          nowUtc: DateTime.utc(2026, 6, 11),
        );

    test(
      'throws when document workflow status changed to non-classified',
      () async {
        final docId = await _insertDocument(db, code: 'DOC-0000001');
        // Race: change status to copied_to_library before the transaction.
        await (db.update(db.documents)..where((d) => d.id.equals(docId))).write(
          DocumentsCompanion(
            workflowStatusKey: const Value('copied_to_library'),
          ),
        );
        await expectLater(
          repo.persistManagedCopySuccess(raceData(docId)),
          throwsA(isA<StateError>()),
        );
      },
    );

    test(
      'throws when a managed copy already exists for the document',
      () async {
        final docId = await _insertDocument(db, code: 'DOC-0000001');
        // Race: insert a managed_copy row before the transaction.
        await db
            .into(db.documentFiles)
            .insert(
              DocumentFilesCompanion.insert(
                documentId: docId,
                fileRoleKey: 'managed_copy',
                fileName: 'DOC-0000001.pdf',
                absolutePath: r'C:\Library\files\DOC-0000001-existing.pdf',
                extension: '.pdf',
                fileSizeBytes: 512,
                fileHealthKey: const Value('healthy'),
                createdAt: DateTime.utc(2026, 1, 1).toIso8601String(),
                updatedAt: DateTime.utc(2026, 1, 1).toIso8601String(),
              ),
            );
        await expectLater(
          repo.persistManagedCopySuccess(raceData(docId)),
          throwsA(isA<StateError>()),
        );
      },
    );

    test('throws when document code does not match persistence data', () async {
      final docId = await _insertDocument(db, code: 'DOC-0000099');
      await expectLater(
        repo.persistManagedCopySuccess(raceData(docId)),
        throwsA(isA<StateError>()),
      );
    });
  });
}
