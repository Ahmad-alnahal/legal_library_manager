// `isNull` is exported by both drift and matcher; keep matcher's for tests.
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/database/seeding/reference_seeder.dart';
import 'package:sqlite3/common.dart';

void main() {
  group('duplicate-group schema', () {
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
            fileRoleKey: 'source_original',
            fileName: 'a.pdf',
            absolutePath: path,
            extension: '.pdf',
            fileSizeBytes: 1024,
            createdAt: nowIso,
            updatedAt: nowIso,
          ),
        );

    Future<int> insertGroup({
      required String groupCode,
      required String sha,
      Value<int?> preferredFileId = const Value.absent(),
      Value<String> reviewStatusKey = const Value.absent(),
    }) => db
        .into(db.duplicateGroups)
        .insert(
          DuplicateGroupsCompanion.insert(
            groupCode: groupCode,
            sha256Hash: sha,
            createdAt: nowIso,
            updatedAt: nowIso,
            preferredFileId: preferredFileId,
            reviewStatusKey: reviewStatusKey,
          ),
        );

    Future<void> addMember(int groupId, int fileId) => db
        .into(db.duplicateGroupMembers)
        .insert(
          DuplicateGroupMembersCompanion.insert(
            duplicateGroupId: groupId,
            fileId: fileId,
            addedAt: nowIso,
          ),
        );

    test('tables and required indexes exist', () async {
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
        containsAll(<String>['duplicate_groups', 'duplicate_group_members']),
      );

      final Set<String> indexes =
          (await db
                  .customSelect(
                    "SELECT name FROM sqlite_master WHERE type = 'index';",
                  )
                  .get())
              .map((QueryRow r) => r.read<String>('name'))
              .toSet();
      expect(indexes, contains('ux_duplicate_groups_sha256_hash'));
      expect(indexes, contains('ix_duplicate_group_members_file_id'));
    });

    test('default and valid review statuses work', () async {
      final int gId = await insertGroup(groupCode: 'G1', sha: 'h1');
      final DuplicateGroup g = await (db.select(
        db.duplicateGroups,
      )..where((d) => d.id.equals(gId))).getSingle();
      expect(g.reviewStatusKey, 'unreviewed');
      expect(g.preferredFileId, isNull);

      await insertGroup(
        groupCode: 'G2',
        sha: 'h2',
        reviewStatusKey: const Value('reviewed'),
      );
      await insertGroup(
        groupCode: 'G3',
        sha: 'h3',
        reviewStatusKey: const Value('archived_for_later'),
      );
    });

    test('invalid review status is rejected', () async {
      expect(
        () => insertGroup(
          groupCode: 'G9',
          sha: 'h9',
          reviewStatusKey: const Value('pending'),
        ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('group_code and sha256_hash are unique', () async {
      await insertGroup(groupCode: 'DUP-GROUP-00001', sha: 'hashA');

      // Duplicate group_code.
      expect(
        () => insertGroup(groupCode: 'DUP-GROUP-00001', sha: 'hashB'),
        throwsA(isA<SqliteException>()),
      );
      // Duplicate sha256_hash.
      expect(
        () => insertGroup(groupCode: 'DUP-GROUP-00002', sha: 'hashA'),
        throwsA(isA<SqliteException>()),
      );
    });

    test('composite membership PK prevents duplicate rows', () async {
      final int docId = await insertDocument();
      final int fileId = await insertFile(docId, r'C:\src\dup.pdf');
      final int gId = await insertGroup(groupCode: 'G1', sha: 'h1');

      await addMember(gId, fileId);
      expect(() => addMember(gId, fileId), throwsA(isA<SqliteException>()));
    });

    test('deleting a group cascades its membership rows', () async {
      final int docId = await insertDocument();
      final int fileId = await insertFile(docId, r'C:\src\dup.pdf');
      final int gId = await insertGroup(groupCode: 'G1', sha: 'h1');
      await addMember(gId, fileId);

      final int deleted = await (db.delete(
        db.duplicateGroups,
      )..where((d) => d.id.equals(gId))).go();
      expect(deleted, 1);
      expect(await db.select(db.duplicateGroupMembers).get(), isEmpty);
      // The referenced file row is untouched.
      expect((await db.select(db.documentFiles).get()).length, 1);
    });

    test('deleting a member-referenced file is restricted', () async {
      final int docId = await insertDocument();
      final int fileId = await insertFile(docId, r'C:\src\dup.pdf');
      final int gId = await insertGroup(groupCode: 'G1', sha: 'h1');
      await addMember(gId, fileId);

      expect(
        () => (db.delete(
          db.documentFiles,
        )..where((f) => f.id.equals(fileId))).go(),
        throwsA(isA<SqliteException>()),
      );
    });

    test(
      'preferred_file_id rejects nonexistent and restricts deletion',
      () async {
        // Nonexistent preferred file is rejected by the FK.
        expect(
          () => insertGroup(
            groupCode: 'G1',
            sha: 'h1',
            preferredFileId: const Value(9999),
          ),
          throwsA(isA<SqliteException>()),
        );

        // A valid preferred file cannot be deleted while referenced.
        final int docId = await insertDocument();
        final int fileId = await insertFile(docId, r'C:\src\pref.pdf');
        await insertGroup(
          groupCode: 'G2',
          sha: 'h2',
          preferredFileId: Value(fileId),
        );
        expect(
          () => (db.delete(
            db.documentFiles,
          )..where((f) => f.id.equals(fileId))).go(),
          throwsA(isA<SqliteException>()),
        );
      },
    );
  });
}
