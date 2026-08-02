// test/features/dashboard/data/dashboard_repository_test.dart

import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/constants/domain_keys.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/database/seeding/reference_seeder.dart';
import 'package:legal_library_manager/features/dashboard/data/repositories/drift_dashboard_repository.dart';
import 'package:legal_library_manager/features/dashboard/domain/entities/activity_source.dart';

void main() {
  group('DriftDashboardRepository', () {
    late AppDatabase db;
    late DriftDashboardRepository repository;

    const String now = '2026-06-21T10:00:00.000Z';
    const String earlier = '2026-06-21T09:00:00.000Z';
    const String earliest = '2026-06-21T08:00:00.000Z';

    setUp(() async {
      db = AppDatabase.inMemory();
      await ReferenceSeeder(db).seedAll();
      repository = DriftDashboardRepository(db);
    });

    tearDown(() => db.close());

    // ── helpers ───────────────────────────────────────────────────────────

    Future<int> addDocument({String status = WorkflowStatusKey.imported}) =>
        db
        .into(db.documents)
        .insert(
          DocumentsCompanion.insert(
            workflowStatusKey: Value(status),
            createdAt: now,
            updatedAt: now,
          ),
        );

    Future<int> addFile(
      int docId, {
      String role = FileRoleKey.sourceOriginal,
      String health = FileHealthKey.healthy,
      String path = '/tmp/file.pdf',
    }) => db
        .into(db.documentFiles)
        .insert(
          DocumentFilesCompanion.insert(
            documentId: docId,
            fileRoleKey: role,
            fileName: 'file.pdf',
            absolutePath: path,
            extension: '.pdf',
            fileSizeBytes: 1024,
            fileHealthKey: Value(health),
            isReadOnlySource: const Value(true),
            createdAt: now,
            updatedAt: now,
          ),
        );

    Future<int> addGroup({required String hash, String code = ''}) => db
        .into(db.duplicateGroups)
        .insert(
          DuplicateGroupsCompanion.insert(
            groupCode: code.isEmpty ? 'GRP-$hash' : code,
            sha256Hash: hash,
            createdAt: now,
            updatedAt: now,
          ),
        );

    Future<void> addMember(int groupId, int fileId) => db
        .into(db.duplicateGroupMembers)
        .insert(
          DuplicateGroupMembersCompanion.insert(
            duplicateGroupId: groupId,
            fileId: fileId,
            addedAt: now,
          ),
        );

    Future<void> addFileEvent({
      String eventType = 'imported',
      String result = 'succeeded',
      String createdAt = now,
    }) => db
        .into(db.fileEvents)
        .insert(
          FileEventsCompanion.insert(
            eventTypeKey: eventType,
            operationId: 'op-${createdAt.hashCode}',
            resultKey: result,
            createdAt: createdAt,
          ),
        );

    Future<void> addOpenEvent({
      required int fileId,
      String target = 'file',
      String result = 'succeeded',
      String createdAt = now,
    }) => db
        .into(db.fileOpenEvents)
        .insert(
          FileOpenEventsCompanion.insert(
            fileId: fileId,
            openTargetKey: target,
            resultKey: result,
            createdAt: createdAt,
          ),
        );

    Future<void> addImportBatch({
      String code = 'IMP-001',
      String status = 'completed',
      String startedAt = now,
    }) => db
        .into(db.importBatches)
        .insert(
          ImportBatchesCompanion.insert(
            batchCode: code,
            sourceFolder: r'C:\source',
            recursiveScan: false,
            statusKey: status,
            startedAt: startedAt,
          ),
        );

    // ── getMetrics ────────────────────────────────────────────────────────

    test('returns all-zero metrics for an empty database', () async {
      final m = await repository.getMetrics();

      expect(m.totalImportedFiles, 0);
      expect(m.needsReview, 0);
      expect(m.inProgress, 0);
      expect(m.classified, 0);
      expect(m.copiedToLibrary, 0);
      expect(m.readyForExport, 0);
      expect(m.duplicateGroups, 0);
      expect(m.corruptedFiles, 0);
      expect(m.totalDocuments, 0);
    });

    test('completionPercent is 0.0 when totalDocuments is 0', () async {
      final m = await repository.getMetrics();
      expect(m.completionPercent, 0.0);
    });

    test('counts total imported files (source_original only)', () async {
      final docId = await addDocument();
      await addFile(docId, role: FileRoleKey.sourceOriginal, path: '/a.pdf');
      await addFile(docId, role: FileRoleKey.managedCopy, path: '/m.pdf');

      final m = await repository.getMetrics();
      expect(m.totalImportedFiles, 1);
      expect(m.totalDocuments, 1);
    });

    test('counts workflow status buckets correctly', () async {
      await addDocument(status: WorkflowStatusKey.needsReview);
      await addDocument(status: WorkflowStatusKey.needsReview);
      await addDocument(status: WorkflowStatusKey.inProgress);
      await addDocument(status: WorkflowStatusKey.classified);
      await addDocument(status: WorkflowStatusKey.copiedToLibrary);
      await addDocument(status: WorkflowStatusKey.readyForExport);
      await addDocument(status: WorkflowStatusKey.imported);

      final m = await repository.getMetrics();
      expect(m.totalDocuments, 7);
      expect(m.needsReview, 2);
      expect(m.inProgress, 1);
      expect(m.classified, 1);
      expect(m.copiedToLibrary, 1);
      expect(m.readyForExport, 1);
    });

    test('counts corrupted files', () async {
      final docId = await addDocument();
      await addFile(docId, health: FileHealthKey.corrupted, path: '/c1.pdf');
      await addFile(docId, health: FileHealthKey.corrupted, path: '/c2.pdf');
      await addFile(docId, health: FileHealthKey.healthy, path: '/h.pdf');

      final m = await repository.getMetrics();
      expect(m.corruptedFiles, 2);
    });

    test('duplicate groups: counts only groups with >= 2 members', () async {
      // Group with 2 members — should count.
      final doc1 = await addDocument();
      final f1 = await addFile(doc1, path: '/f1.pdf');
      final f2 = await addFile(doc1, path: '/f2.pdf');
      final g1 = await addGroup(hash: 'a' * 64);
      await addMember(g1, f1);
      await addMember(g1, f2);

      // Group with only 1 member — must NOT count.
      final doc2 = await addDocument();
      final f3 = await addFile(doc2, path: '/f3.pdf');
      final g2 = await addGroup(hash: 'b' * 64);
      await addMember(g2, f3);

      final m = await repository.getMetrics();
      expect(m.duplicateGroups, 1);
    });

    test('completionPercent formula: (copied + ready) / total', () async {
      await addDocument(status: WorkflowStatusKey.copiedToLibrary);
      await addDocument(status: WorkflowStatusKey.readyForExport);
      await addDocument(status: WorkflowStatusKey.imported);
      await addDocument(status: WorkflowStatusKey.imported);

      final m = await repository.getMetrics();
      expect(m.totalDocuments, 4);
      expect(m.copiedToLibrary, 1);
      expect(m.readyForExport, 1);
      expect(m.completionPercent, closeTo(0.5, 0.001));
    });

    // ── getRecentActivity ─────────────────────────────────────────────────

    test('returns empty list when no activity records exist', () async {
      final items = await repository.getRecentActivity();
      expect(items, isEmpty);
    });

    test('returns file_events in newest-first order', () async {
      await addFileEvent(eventType: 'imported', createdAt: earliest);
      await addFileEvent(eventType: 'hash_completed', createdAt: earlier);
      await addFileEvent(eventType: 'copy_verified', createdAt: now);

      final items = await repository.getRecentActivity();
      expect(items, hasLength(3));
      expect(items[0].eventKey, 'copy_verified');
      expect(items[1].eventKey, 'hash_completed');
      expect(items[2].eventKey, 'imported');
      for (final item in items) {
        expect(item.source, ActivitySource.fileEvent);
      }
    });

    test('returns file_open_events with correct source', () async {
      final docId = await addDocument();
      final fileId = await addFile(docId);
      await addOpenEvent(fileId: fileId, target: 'file', createdAt: now);

      final items = await repository.getRecentActivity();
      expect(items, hasLength(1));
      expect(items[0].source, ActivitySource.fileOpenEvent);
      expect(items[0].eventKey, 'file');
      expect(items[0].fileId, fileId);
    });

    test('returns import_batches with batch_code and result_key', () async {
      await addImportBatch(
        code: 'IMP-002',
        status: 'completed',
        startedAt: now,
      );

      final items = await repository.getRecentActivity();
      expect(items, hasLength(1));
      expect(items[0].source, ActivitySource.importBatch);
      expect(items[0].eventKey, 'import_batch');
      expect(items[0].batchCode, 'IMP-002');
      expect(items[0].resultKey, 'completed');
    });

    test('merges all three sources newest-first', () async {
      await addFileEvent(createdAt: earliest);
      final docId = await addDocument();
      final fileId = await addFile(docId);
      await addOpenEvent(fileId: fileId, createdAt: earlier);
      await addImportBatch(startedAt: now);

      final items = await repository.getRecentActivity();
      expect(items, hasLength(3));
      expect(items[0].source, ActivitySource.importBatch);
      expect(items[1].source, ActivitySource.fileOpenEvent);
      expect(items[2].source, ActivitySource.fileEvent);
    });

    test('respects limit parameter', () async {
      for (var i = 0; i < 5; i++) {
        await addFileEvent(
          eventType: 'imported',
          createdAt: '2026-06-21T0$i:00:00.000Z',
        );
      }

      final items = await repository.getRecentActivity(limit: 3);
      expect(items, hasLength(3));
    });

    test('rejects invalid limit values', () async {
      await expectLater(
        repository.getRecentActivity(limit: 0),
        throwsArgumentError,
      );
      await expectLater(
        repository.getRecentActivity(limit: 201),
        throwsArgumentError,
      );
    });
  });
}
