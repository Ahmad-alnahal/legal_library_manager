// `isNull` is exported by both drift and matcher; keep matcher's for tests.
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/database/seeding/reference_seeder.dart';
import 'package:sqlite3/common.dart';

void main() {
  group('documents / document_files schema', () {
    late AppDatabase db;
    const String nowIso = '2026-06-06T10:00:00Z';

    setUp(() async {
      db = AppDatabase.inMemory();
      // Reference rows must exist so the default reference FKs resolve.
      await ReferenceSeeder(db).seedAll();
    });

    tearDown(() async {
      await db.close();
    });

    Future<int> insertDocument({
      Value<String?> documentCode = const Value.absent(),
      Value<int?> documentTypeId = const Value.absent(),
      Value<int?> publicationYear = const Value.absent(),
    }) {
      return db
          .into(db.documents)
          .insert(
            DocumentsCompanion.insert(
              createdAt: nowIso,
              updatedAt: nowIso,
              documentCode: documentCode,
              documentTypeId: documentTypeId,
              publicationYear: publicationYear,
            ),
          );
    }

    Future<int> insertFile({
      required int documentId,
      String absolutePath = r'C:\src\a.pdf',
      int fileSizeBytes = 1024,
      String fileRoleKey = 'source_original',
    }) {
      return db
          .into(db.documentFiles)
          .insert(
            DocumentFilesCompanion.insert(
              documentId: documentId,
              fileRoleKey: fileRoleKey,
              fileName: 'a.pdf',
              absolutePath: absolutePath,
              extension: '.pdf',
              fileSizeBytes: fileSizeBytes,
              createdAt: nowIso,
              updatedAt: nowIso,
            ),
          );
    }

    test('tables and required indexes exist', () async {
      final List<QueryRow> tableRows = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'table';")
          .get();
      final Set<String> tables = tableRows
          .map((QueryRow r) => r.read<String>('name'))
          .toSet();
      expect(tables, containsAll(<String>['documents', 'document_files']));

      final List<QueryRow> indexRows = await db
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'index';")
          .get();
      final Set<String> indexes = indexRows
          .map((QueryRow r) => r.read<String>('name'))
          .toSet();

      const List<String> requiredIndexes = [
        'ux_documents_document_code',
        'ix_documents_workflow_status_key',
        'ix_documents_document_type_id',
        'ix_documents_primary_main_category_id',
        'ix_documents_primary_sub_category_id',
        'ix_documents_publication_year',
        'ix_documents_country_key',
        'ix_documents_trust_level_key',
        'ix_documents_metadata_quality_key',
        'ix_documents_updated_at',
        'ux_document_files_absolute_path',
        'ix_document_files_document_id',
        'ix_document_files_sha256_hash',
        'ix_document_files_file_role_key',
        'ix_document_files_file_health_key',
        'ix_document_files_extension',
      ];
      for (final String name in requiredIndexes) {
        expect(indexes, contains(name), reason: 'missing index $name');
      }
    });

    test('reference and boolean defaults apply', () async {
      final int docId = await insertDocument();
      final Document doc = await (db.select(
        db.documents,
      )..where((d) => d.id.equals(docId))).getSingle();
      expect(doc.trustLevelKey, 'unverified');
      expect(doc.usageRightsKey, 'unknown');
      expect(doc.metadataQualityKey, 'low');
      expect(doc.workflowStatusKey, 'imported');
      expect(doc.documentCode, isNull);

      await insertFile(documentId: docId);
      final DocumentFile file = await (db.select(
        db.documentFiles,
      )..where((f) => f.documentId.equals(docId))).getSingle();
      expect(file.fileHealthKey, 'unknown');
      expect(file.isReadOnlySource, isFalse);
      expect(file.isPreferred, isFalse);
    });

    test('document_code is unique', () async {
      await insertDocument(documentCode: const Value('DOC-0000001'));
      expect(
        () => insertDocument(documentCode: const Value('DOC-0000001')),
        throwsA(isA<SqliteException>()),
      );
    });

    test('absolute_path is unique', () async {
      final int docId = await insertDocument();
      await insertFile(documentId: docId, absolutePath: r'C:\src\unique.pdf');
      expect(
        () => insertFile(documentId: docId, absolutePath: r'C:\src\unique.pdf'),
        throwsA(isA<SqliteException>()),
      );
    });

    test('foreign keys are enforced', () async {
      // Non-existent document_type_id.
      expect(
        () => insertDocument(documentTypeId: const Value(9999)),
        throwsA(isA<SqliteException>()),
      );

      // Non-existent document_id on a file.
      expect(
        () => insertFile(documentId: 9999),
        throwsA(isA<SqliteException>()),
      );

      // Non-existent file_role_key on a file.
      final int docId = await insertDocument();
      expect(
        () => insertFile(documentId: docId, fileRoleKey: 'not_a_role'),
        throwsA(isA<SqliteException>()),
      );
    });

    test('document-to-files delete is restricted', () async {
      final int docId = await insertDocument();
      await insertFile(documentId: docId);

      // RESTRICT: cannot delete a document that still has files.
      expect(
        () => (db.delete(db.documents)..where((d) => d.id.equals(docId))).go(),
        throwsA(isA<SqliteException>()),
      );

      // After removing the file, deleting the document succeeds.
      await (db.delete(
        db.documentFiles,
      )..where((f) => f.documentId.equals(docId))).go();
      final int deleted = await (db.delete(
        db.documents,
      )..where((d) => d.id.equals(docId))).go();
      expect(deleted, 1);
    });

    test('negative file size is rejected', () async {
      final int docId = await insertDocument();
      expect(
        () => insertFile(documentId: docId, fileSizeBytes: -1),
        throwsA(isA<SqliteException>()),
      );
    });

    test('unreasonable publication year is rejected', () async {
      expect(
        () => insertDocument(publicationYear: const Value(800)),
        throwsA(isA<SqliteException>()),
      );
      expect(
        () => insertDocument(publicationYear: const Value(99999)),
        throwsA(isA<SqliteException>()),
      );

      // A sensible year is accepted.
      final int id = await insertDocument(publicationYear: const Value(2020));
      expect(id, greaterThan(0));
    });
  });
}
