// test/features/export/data/drift_export_batch_repository_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/database/seeding/reference_seeder.dart';
import 'package:legal_library_manager/features/export/data/repositories/drift_export_batch_repository.dart';
import 'package:legal_library_manager/features/export/domain/entities/export_batch_document_entry.dart';

import '../../documents/support/document_test_support.dart';

void main() {
  late AppDatabase db;
  late DriftExportBatchRepository repo;

  setUp(() async {
    db = AppDatabase.inMemory();
    await ReferenceSeeder(db).seedAll();
    repo = DriftExportBatchRepository(db);
  });

  tearDown(() => db.close());

  group('allocateBatchCode', () {
    test('first code for a date is NNN=001', () async {
      final code = await repo.allocateBatchCode(DateTime.utc(2026, 7, 18));
      expect(code, 'EXP-2026-07-18-001');
    });

    test('increments NNN correctly when one already exists', () async {
      await repo.createBatch(
        batchCode: 'EXP-2026-07-18-001',
        exportPath: r'D:\Export\EXP-2026-07-18-001',
        createdAt: DateTime.utc(2026, 7, 18),
      );

      final code = await repo.allocateBatchCode(DateTime.utc(2026, 7, 18));
      expect(code, 'EXP-2026-07-18-002');
    });

    test('NNN resets for a new date', () async {
      await repo.createBatch(
        batchCode: 'EXP-2026-07-18-003',
        exportPath: r'D:\Export\EXP-2026-07-18-003',
        createdAt: DateTime.utc(2026, 7, 18),
      );

      final code = await repo.allocateBatchCode(DateTime.utc(2026, 7, 19));
      expect(code, 'EXP-2026-07-19-001');
    });
  });

  group('createBatch', () {
    test('inserts with status preparing', () async {
      final id = await repo.createBatch(
        batchCode: 'EXP-2026-07-18-001',
        exportPath: r'D:\Export\EXP-2026-07-18-001',
        createdAt: DateTime.utc(2026, 7, 18, 9),
      );

      final row = await (db.select(
        db.exportBatches,
      )..where((b) => b.id.equals(id))).getSingle();
      expect(row.statusKey, 'preparing');
      expect(row.documentCount, 0);
      expect(row.totalSizeBytes, 0);
    });
  });

  group('insertBatchDocuments', () {
    test('inserts all entries', () async {
      final batchId = await repo.createBatch(
        batchCode: 'EXP-2026-07-18-001',
        exportPath: r'D:\Export\EXP-2026-07-18-001',
        createdAt: DateTime.utc(2026, 7, 18, 9),
      );
      final doc1 = await insertDocument(db);
      final doc2 = await insertDocument(db);
      final file1 = await addFile(
        db,
        doc1,
        role: 'managed_copy',
        health: 'healthy',
      );
      final file2 = await addFile(
        db,
        doc2,
        role: 'managed_copy',
        health: 'healthy',
      );

      await repo.insertBatchDocuments([
        ExportBatchDocumentEntry(
          batchId: batchId,
          documentId: doc1,
          managedFileId: file1,
          sha256Hash: 'a' * 64,
          createdAt: DateTime.utc(2026, 7, 18, 9),
        ),
        ExportBatchDocumentEntry(
          batchId: batchId,
          documentId: doc2,
          managedFileId: file2,
          sha256Hash: 'b' * 64,
          createdAt: DateTime.utc(2026, 7, 18, 9),
        ),
      ]);

      final rows = await (db.select(
        db.exportBatchDocuments,
      )..where((d) => d.exportBatchId.equals(batchId))).get();
      expect(rows, hasLength(2));
    });
  });

  group('finalizeBatch', () {
    test('updates status, count, size, completedAt', () async {
      final batchId = await repo.createBatch(
        batchCode: 'EXP-2026-07-18-001',
        exportPath: r'D:\Export\EXP-2026-07-18-001',
        createdAt: DateTime.utc(2026, 7, 18, 9),
      );

      await repo.finalizeBatch(
        batchId: batchId,
        statusKey: 'verified',
        documentCount: 2,
        totalSizeBytes: 2048,
        completedAt: DateTime.utc(2026, 7, 18, 10),
      );

      final row = await (db.select(
        db.exportBatches,
      )..where((b) => b.id.equals(batchId))).getSingle();
      expect(row.statusKey, 'verified');
      expect(row.documentCount, 2);
      expect(row.totalSizeBytes, 2048);
      expect(row.completedAt, '2026-07-18T10:00:00.000Z');
    });
  });

  group('listBatches', () {
    test('returns newest first', () async {
      await repo.createBatch(
        batchCode: 'EXP-2026-07-18-001',
        exportPath: r'D:\Export\EXP-2026-07-18-001',
        createdAt: DateTime.utc(2026, 7, 18, 9),
      );
      await repo.createBatch(
        batchCode: 'EXP-2026-07-18-002',
        exportPath: r'D:\Export\EXP-2026-07-18-002',
        createdAt: DateTime.utc(2026, 7, 18, 10),
      );

      final batches = await repo.listBatches();
      expect(batches, hasLength(2));
      expect(batches[0].batchCode, 'EXP-2026-07-18-002');
      expect(batches[1].batchCode, 'EXP-2026-07-18-001');
    });
  });
}
