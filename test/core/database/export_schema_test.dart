// `isNull` is exported by both drift and matcher; keep matcher's for tests.
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/constants/domain_keys.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/database/seeding/reference_seeder.dart';
import 'package:sqlite3/common.dart';

void main() {
  group('export schema', () {
    late AppDatabase db;
    const String nowIso = '2026-06-06T10:00:00Z';

    setUp(() async {
      db = AppDatabase.inMemory();
      await ReferenceSeeder(db).seedAll();
    });

    tearDown(() async {
      await db.close();
    });

    Future<int> insertDocument() => db
        .into(db.documents)
        .insert(
          DocumentsCompanion.insert(createdAt: nowIso, updatedAt: nowIso),
        );

    Future<int> insertFile(int documentId, String path) => db
        .into(db.documentFiles)
        .insert(
          DocumentFilesCompanion.insert(
            documentId: documentId,
            fileRoleKey: FileRoleKey.managedCopy,
            fileName: 'DOC-0000001.pdf',
            absolutePath: path,
            extension: '.pdf',
            fileSizeBytes: 1024,
            createdAt: nowIso,
            updatedAt: nowIso,
          ),
        );

    Future<int> insertBatch({
      String batchCode = 'BATCH-2026-06-06-001',
      String statusKey = 'preparing',
      Value<int> documentCount = const Value.absent(),
      Value<int> totalSizeBytes = const Value.absent(),
    }) => db
        .into(db.exportBatches)
        .insert(
          ExportBatchesCompanion.insert(
            batchCode: batchCode,
            exportPath: r'C:\Library\exports\batch1',
            statusKey: statusKey,
            createdAt: nowIso,
            documentCount: documentCount,
            totalSizeBytes: totalSizeBytes,
          ),
        );

    Future<void> addSnapshot(int batchId, int docId, int fileId) => db
        .into(db.exportBatchDocuments)
        .insert(
          ExportBatchDocumentsCompanion.insert(
            exportBatchId: batchId,
            documentId: docId,
            managedFileId: fileId,
            sha256Hash: 'a' * 64,
            createdAt: nowIso,
          ),
        );

    test('export tables and required index exist', () async {
      final Set<String> tables =
          (await db
                  .customSelect(
                    "SELECT name FROM sqlite_master WHERE type = 'table';",
                  )
                  .get())
              .map((QueryRow r) => r.read<String>('name'))
              .toSet();
      expect(
        tables,
        containsAll(<String>['export_batches', 'export_batch_documents']),
      );

      final Set<String> indexes =
          (await db
                  .customSelect(
                    "SELECT name FROM sqlite_master WHERE type = 'index';",
                  )
                  .get())
              .map((QueryRow r) => r.read<String>('name'))
              .toSet();
      expect(indexes, contains('ix_export_batches_created_at'));
    });

    test('valid and invalid export statuses', () async {
      const List<String> valid = [
        'preparing',
        'completed',
        'failed',
        'verified',
        'uploaded',
      ];
      for (int i = 0; i < valid.length; i++) {
        expect(
          await insertBatch(batchCode: 'B$i', statusKey: valid[i]),
          greaterThan(0),
        );
      }
      expect(
        () => insertBatch(batchCode: 'BX', statusKey: 'archived'),
        throwsA(isA<SqliteException>()),
      );
    });

    test('defaults apply and negative count/size are rejected', () async {
      final int id = await insertBatch();
      final ExportBatch batch = await (db.select(
        db.exportBatches,
      )..where((b) => b.id.equals(id))).getSingle();
      expect(batch.documentCount, 0);
      expect(batch.totalSizeBytes, 0);
      expect(batch.checksumAlgorithm, 'SHA-256');

      expect(
        () => insertBatch(batchCode: 'N1', documentCount: const Value(-1)),
        throwsA(isA<SqliteException>()),
      );
      expect(
        () => insertBatch(batchCode: 'N2', totalSizeBytes: const Value(-5)),
        throwsA(isA<SqliteException>()),
      );
    });

    test('batch_code is unique', () async {
      await insertBatch(batchCode: 'DUP');
      expect(
        () => insertBatch(batchCode: 'DUP'),
        throwsA(isA<SqliteException>()),
      );
    });

    test('composite export-document identity is enforced', () async {
      final int batchId = await insertBatch();
      final int docId = await insertDocument();
      final int fileId = await insertFile(docId, r'C:\lib\DOC-0000001.pdf');
      await addSnapshot(batchId, docId, fileId);
      // Same (export_batch_id, document_id) violates the composite PK.
      expect(
        () => addSnapshot(batchId, docId, fileId),
        throwsA(isA<SqliteException>()),
      );
    });

    test(
      'deleting an export batch cascades snapshots, preserves docs/files',
      () async {
        final int batchId = await insertBatch();
        final int docId = await insertDocument();
        final int fileId = await insertFile(docId, r'C:\lib\DOC-0000001.pdf');
        await addSnapshot(batchId, docId, fileId);

        final int deleted = await (db.delete(
          db.exportBatches,
        )..where((b) => b.id.equals(batchId))).go();
        expect(deleted, 1);
        expect(await db.select(db.exportBatchDocuments).get(), isEmpty);
        expect((await db.select(db.documents).get()).length, 1);
        expect((await db.select(db.documentFiles).get()).length, 1);
      },
    );

    test(
      'referenced documents/files cannot be deleted while snapshots exist',
      () async {
        final int batchId = await insertBatch();
        final int docId = await insertDocument();
        final int fileId = await insertFile(docId, r'C:\lib\DOC-0000001.pdf');
        await addSnapshot(batchId, docId, fileId);

        expect(
          () =>
              (db.delete(db.documents)..where((d) => d.id.equals(docId))).go(),
          throwsA(isA<SqliteException>()),
        );
        expect(
          () => (db.delete(
            db.documentFiles,
          )..where((f) => f.id.equals(fileId))).go(),
          throwsA(isA<SqliteException>()),
        );
      },
    );

    test('invalid/nonexistent snapshot references are rejected', () async {
      final int batchId = await insertBatch();
      final int docId = await insertDocument();
      final int fileId = await insertFile(docId, r'C:\lib\DOC-0000001.pdf');

      // Nonexistent export batch.
      expect(
        () => addSnapshot(9999, docId, fileId),
        throwsA(isA<SqliteException>()),
      );
      // Nonexistent document.
      expect(
        () => addSnapshot(batchId, 9999, fileId),
        throwsA(isA<SqliteException>()),
      );
      // Nonexistent managed file.
      expect(
        () => addSnapshot(batchId, docId, 9999),
        throwsA(isA<SqliteException>()),
      );
    });
  });
}
