// `isNull` is exported by both drift and matcher; keep matcher's for tests.
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/database/seeding/reference_seeder.dart';
import 'package:sqlite3/common.dart';

void main() {
  group('audit / import / settings schema', () {
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
            fileRoleKey: 'source_original',
            fileName: 'a.pdf',
            absolutePath: path,
            extension: '.pdf',
            fileSizeBytes: 1024,
            createdAt: nowIso,
            updatedAt: nowIso,
          ),
        );

    Future<int> insertEvent({
      Value<int?> documentId = const Value.absent(),
      Value<int?> fileId = const Value.absent(),
      String type = 'imported',
      String result = 'succeeded',
    }) => db
        .into(db.fileEvents)
        .insert(
          FileEventsCompanion.insert(
            eventTypeKey: type,
            operationId: 'op-1',
            resultKey: result,
            createdAt: nowIso,
            documentId: documentId,
            fileId: fileId,
          ),
        );

    Future<int> insertOpenEvent({
      required int fileId,
      String target = 'file',
      String result = 'succeeded',
    }) => db
        .into(db.fileOpenEvents)
        .insert(
          FileOpenEventsCompanion.insert(
            fileId: fileId,
            openTargetKey: target,
            resultKey: result,
            createdAt: nowIso,
          ),
        );

    Future<int> insertBatch({
      String batchCode = 'B1',
      Value<int> discoveredCount = const Value.absent(),
    }) => db
        .into(db.importBatches)
        .insert(
          ImportBatchesCompanion.insert(
            batchCode: batchCode,
            sourceFolder: r'C:\src',
            recursiveScan: true,
            statusKey: 'running',
            startedAt: nowIso,
            discoveredCount: discoveredCount,
          ),
        );

    Future<void> addBatchFile(int batchId, int fileId) => db
        .into(db.importBatchFiles)
        .insert(
          ImportBatchFilesCompanion.insert(
            importBatchId: batchId,
            fileId: fileId,
            resultKey: 'imported_new',
            createdAt: nowIso,
          ),
        );

    test('all five tables and required indexes exist', () async {
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
        containsAll(<String>[
          'file_events',
          'file_open_events',
          'import_batches',
          'import_batch_files',
          'settings',
        ]),
      );

      final Set<String> indexes =
          (await db
                  .customSelect(
                    "SELECT name FROM sqlite_master WHERE type = 'index';",
                  )
                  .get())
              .map((QueryRow r) => r.read<String>('name'))
              .toSet();
      expect(
        indexes,
        containsAll(<String>[
          'ix_file_events_document_created',
          'ix_file_events_file_created',
          'ix_file_events_operation_id',
          'ix_file_open_events_file_created',
          'ix_import_batches_started_at',
        ]),
      );
    });

    test('file_events: valid/invalid event keys and results', () async {
      // Valid (with NULL references allowed).
      final int id = await insertEvent();
      expect(id, greaterThan(0));

      expect(
        () => insertEvent(type: 'teleported'),
        throwsA(isA<SqliteException>()),
      );
      expect(
        () => insertEvent(result: 'maybe'),
        throwsA(isA<SqliteException>()),
      );
    });

    test('file_events: nullable references and FK restrictions', () async {
      // Both references NULL is accepted.
      final int eid = await insertEvent();
      final FileEvent row = await (db.select(
        db.fileEvents,
      )..where((e) => e.id.equals(eid))).getSingle();
      expect(row.documentId, isNull);
      expect(row.fileId, isNull);

      // Nonexistent references are rejected.
      expect(
        () => insertEvent(documentId: const Value(9999)),
        throwsA(isA<SqliteException>()),
      );
      expect(
        () => insertEvent(fileId: const Value(9999)),
        throwsA(isA<SqliteException>()),
      );
    });

    test(
      'file_open_events: target/result constraints and required file',
      () async {
        final int docId = await insertDocument();
        final int fileId = await insertFile(docId, r'C:\src\a.pdf');

        expect(await insertOpenEvent(fileId: fileId), greaterThan(0));
        expect(
          () => insertOpenEvent(fileId: fileId, target: 'window'),
          throwsA(isA<SqliteException>()),
        );
        expect(
          () => insertOpenEvent(fileId: fileId, result: 'denied'),
          throwsA(isA<SqliteException>()),
        );
        // Nonexistent file is rejected.
        expect(
          () => insertOpenEvent(fileId: 9999),
          throwsA(isA<SqliteException>()),
        );
      },
    );

    test('import_batches: count defaults and negative rejection', () async {
      final int id = await insertBatch();
      final batch = await (db.select(
        db.importBatches,
      )..where((b) => b.id.equals(id))).getSingle();
      expect(batch.discoveredCount, 0);
      expect(batch.importedCount, 0);
      expect(batch.duplicateCount, 0);
      expect(batch.failedCount, 0);

      expect(
        () => insertBatch(batchCode: 'B2', discoveredCount: const Value(-1)),
        throwsA(isA<SqliteException>()),
      );
    });

    test('unique batch_code and composite import-file identity', () async {
      final int batchId = await insertBatch(batchCode: 'BATCH-001');
      expect(
        () => insertBatch(batchCode: 'BATCH-001'),
        throwsA(isA<SqliteException>()),
      );

      final int docId = await insertDocument();
      final int fileId = await insertFile(docId, r'C:\src\a.pdf');
      await addBatchFile(batchId, fileId);
      // Same (import_batch_id, file_id) violates the composite primary key.
      expect(
        () => addBatchFile(batchId, fileId),
        throwsA(isA<SqliteException>()),
      );
    });

    test(
      'deleting an import batch cascades join rows but preserves files',
      () async {
        final int batchId = await insertBatch();
        final int docId = await insertDocument();
        final int fileId = await insertFile(docId, r'C:\src\a.pdf');
        await addBatchFile(batchId, fileId);

        final int deleted = await (db.delete(
          db.importBatches,
        )..where((b) => b.id.equals(batchId))).go();
        expect(deleted, 1);
        expect(await db.select(db.importBatchFiles).get(), isEmpty);
        expect((await db.select(db.documentFiles).get()).length, 1);
      },
    );

    test(
      'referenced files/documents cannot be deleted while records exist',
      () async {
        final int docId = await insertDocument();
        final int fileId = await insertFile(docId, r'C:\src\a.pdf');

        // file_events -> document_files RESTRICT.
        await insertEvent(fileId: Value(fileId));
        expect(
          () => (db.delete(
            db.documentFiles,
          )..where((f) => f.id.equals(fileId))).go(),
          throwsA(isA<SqliteException>()),
        );

        // file_events -> documents RESTRICT (document with no files of its own).
        final int convDoc = await insertDocument();
        await insertEvent(documentId: Value(convDoc));
        expect(
          () => (db.delete(
            db.documents,
          )..where((d) => d.id.equals(convDoc))).go(),
          throwsA(isA<SqliteException>()),
        );

        // file_open_events -> document_files RESTRICT.
        final int doc2 = await insertDocument();
        final int file2 = await insertFile(doc2, r'C:\src\b.pdf');
        await insertOpenEvent(fileId: file2);
        expect(
          () => (db.delete(
            db.documentFiles,
          )..where((f) => f.id.equals(file2))).go(),
          throwsA(isA<SqliteException>()),
        );

        // import_batch_files -> document_files RESTRICT.
        final int batchId = await insertBatch(batchCode: 'B-keep');
        final int doc3 = await insertDocument();
        final int file3 = await insertFile(doc3, r'C:\src\c.pdf');
        await addBatchFile(batchId, file3);
        expect(
          () => (db.delete(
            db.documentFiles,
          )..where((f) => f.id.equals(file3))).go(),
          throwsA(isA<SqliteException>()),
        );
      },
    );

    test('settings: key uniqueness and required fields', () async {
      await db
          .into(db.settings)
          .insert(
            SettingsCompanion.insert(
              key: 'managed_library_root',
              value: r'C:\Library',
              updatedAt: nowIso,
            ),
          );
      // Duplicate key (primary key) is rejected.
      expect(
        () => db
            .into(db.settings)
            .insert(
              SettingsCompanion.insert(
                key: 'managed_library_root',
                value: r'D:\Other',
                updatedAt: nowIso,
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
      // Required value cannot be NULL (raw insert to bypass the typed API).
      expect(
        () => db.customStatement(
          "INSERT INTO settings (key, updated_at) VALUES ('k', '$nowIso');",
        ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('import_batch_files companion requires both IDs', () async {
      final int batchId = await insertBatch();
      // The typed companion requires both IDs at compile time; an omission is
      // only attemptable via raw SQL, where the composite PK columns are NOT
      // NULL and reject it.
      expect(
        () => db.customStatement(
          'INSERT INTO import_batch_files (import_batch_id, result_key, '
          "created_at) VALUES ($batchId, 'r', '$nowIso');",
        ),
        throwsA(isA<SqliteException>()),
      );
    });
  });
}
