// `isNull` is exported by both drift and matcher; keep matcher's for tests.
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/constants/domain_keys.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/database/seeding/reference_seeder.dart';
import 'package:sqlite3/common.dart';

void main() {
  group('file_conversions schema', () {
    late AppDatabase db;
    const String nowIso = '2026-06-06T10:00:00Z';

    setUp(() async {
      db = AppDatabase.inMemory();
      // file_roles / file_health_statuses back the document_files defaults.
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
            fileRoleKey: FileRoleKey.sourceOriginal,
            fileName: 'a.pdf',
            absolutePath: path,
            extension: '.pdf',
            fileSizeBytes: 1024,
            createdAt: nowIso,
            updatedAt: nowIso,
          ),
        );

    Future<int> insertConversion({
      required int documentId,
      required int sourceFileId,
      String statusKey = 'pending_conversion',
      Value<int?> outputFileId = const Value.absent(),
    }) => db
        .into(db.fileConversions)
        .insert(
          FileConversionsCompanion.insert(
            documentId: documentId,
            sourceFileId: sourceFileId,
            statusKey: statusKey,
            createdAt: nowIso,
            updatedAt: nowIso,
            outputFileId: outputFileId,
          ),
        );

    test('table exists', () async {
      final Set<String> tables =
          (await db
                  .customSelect(
                    "SELECT name FROM sqlite_master WHERE type = 'table';",
                  )
                  .get())
              .map((QueryRow r) => r.read<String>('name'))
              .toSet();
      expect(tables, contains('file_conversions'));
    });

    test('required fields and all valid statuses work', () async {
      final int docId = await insertDocument();
      final int srcId = await insertFile(docId, r'C:\src\a.pdf');

      const List<String> statuses = [
        'not_required',
        'pending_conversion',
        'converting',
        'conversion_succeeded',
        'needs_conversion_review',
        'conversion_failed',
        'conversion_approved',
      ];
      for (final String status in statuses) {
        final int id = await insertConversion(
          documentId: docId,
          sourceFileId: srcId,
          statusKey: status,
        );
        expect(id, greaterThan(0));
      }
      expect(
        (await db.select(db.fileConversions).get()).length,
        statuses.length,
      );
    });

    test('invalid status is rejected', () async {
      final int docId = await insertDocument();
      final int srcId = await insertFile(docId, r'C:\src\a.pdf');
      expect(
        () => insertConversion(
          documentId: docId,
          sourceFileId: srcId,
          statusKey: 'exporting',
        ),
        throwsA(isA<SqliteException>()),
      );
    });

    test(
      'nullable fields and nullable quality_approved are accepted',
      () async {
        final int docId = await insertDocument();
        final int srcId = await insertFile(docId, r'C:\src\a.pdf');
        final int id = await insertConversion(
          documentId: docId,
          sourceFileId: srcId,
          statusKey: 'pending_conversion',
        );

        final FileConversion row = await (db.select(
          db.fileConversions,
        )..where((c) => c.id.equals(id))).getSingle();
        expect(row.outputFileId, isNull);
        expect(row.qualityApproved, isNull);
        expect(row.converterKey, isNull);
        expect(row.startedAt, isNull);
        expect(row.errorCode, isNull);
        expect(row.errorMessageSafe, isNull);
      },
    );

    test(
      'nonexistent document / source / output references are rejected',
      () async {
        final int docId = await insertDocument();
        final int srcId = await insertFile(docId, r'C:\src\a.pdf');

        // Nonexistent document.
        expect(
          () => insertConversion(documentId: 9999, sourceFileId: srcId),
          throwsA(isA<SqliteException>()),
        );
        // Nonexistent source file.
        expect(
          () => insertConversion(documentId: docId, sourceFileId: 9999),
          throwsA(isA<SqliteException>()),
        );
        // Nonexistent output file.
        expect(
          () => insertConversion(
            documentId: docId,
            sourceFileId: srcId,
            outputFileId: const Value(9999),
          ),
          throwsA(isA<SqliteException>()),
        );
      },
    );

    test('deleting a referenced document is restricted', () async {
      // A document with no files of its own, referenced only by the conversion,
      // isolates the file_conversions -> documents RESTRICT behavior.
      final int hostDoc = await insertDocument();
      final int srcId = await insertFile(hostDoc, r'C:\src\a.pdf');
      final int convDoc = await insertDocument();
      await insertConversion(documentId: convDoc, sourceFileId: srcId);

      expect(
        () =>
            (db.delete(db.documents)..where((d) => d.id.equals(convDoc))).go(),
        throwsA(isA<SqliteException>()),
      );
    });

    test('deleting a referenced source or output file is restricted', () async {
      final int docId = await insertDocument();
      final int srcId = await insertFile(docId, r'C:\src\source.pdf');
      final int outId = await insertFile(docId, r'C:\src\output.pdf');
      await insertConversion(
        documentId: docId,
        sourceFileId: srcId,
        outputFileId: Value(outId),
      );

      expect(
        () => (db.delete(
          db.documentFiles,
        )..where((f) => f.id.equals(srcId))).go(),
        throwsA(isA<SqliteException>()),
      );
      expect(
        () => (db.delete(
          db.documentFiles,
        )..where((f) => f.id.equals(outId))).go(),
        throwsA(isA<SqliteException>()),
      );
    });
  });
}
