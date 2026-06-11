// test/features/file_open/drift_file_open_repository_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/database/seeding/reference_seeder.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/features/file_open/data/repositories/drift_file_open_repository.dart';
import 'package:legal_library_manager/features/file_open/domain/entities/open_target.dart';

/// Fixed-timestamp [Clock] for deterministic UTC strings in tests.
class _FixedClock extends Clock {
  const _FixedClock();

  static const String fixedIso = '2026-06-10T12:00:00.000Z';

  @override
  DateTime nowUtc() => DateTime.parse(fixedIso);
}

/// Seeds the minimal reference rows required by [document_files] FK constraints.
Future<void> _seedReferences(AppDatabase db) async {
  await ReferenceSeeder(db).seedAll();
}

/// Inserts one [documents] row and returns its ID.
Future<int> _insertDocument(AppDatabase db) => db
    .into(db.documents)
    .insert(
      DocumentsCompanion.insert(
        createdAt: '2026-06-10T00:00:00.000Z',
        updatedAt: '2026-06-10T00:00:00.000Z',
      ),
    );

/// Inserts one [document_files] row and returns its ID.
Future<int> _insertFile(
  AppDatabase db, {
  required int documentId,
  String path = r'C:\Library\sample.pdf',
  String extension = '.pdf',
}) => db
    .into(db.documentFiles)
    .insert(
      DocumentFilesCompanion.insert(
        documentId: documentId,
        fileRoleKey: 'source_original',
        fileName: 'sample.pdf',
        absolutePath: path,
        extension: extension,
        fileSizeBytes: 1024,
        createdAt: '2026-06-10T00:00:00.000Z',
        updatedAt: '2026-06-10T00:00:00.000Z',
      ),
    );

void main() {
  group('DriftFileOpenRepository', () {
    late AppDatabase db;
    late DriftFileOpenRepository repo;

    setUp(() async {
      db = AppDatabase.inMemory();
      await _seedReferences(db);
      repo = DriftFileOpenRepository(db, const _FixedClock());
    });

    tearDown(() => db.close());

    // -----------------------------------------------------------------------
    // loadFileRecord
    // -----------------------------------------------------------------------

    group('loadFileRecord', () {
      test('returns null for a nonexistent file ID', () async {
        final record = await repo.loadFileRecord(9999);
        expect(record, isNull);
      });

      test('returns correct record for an existing file', () async {
        final docId = await _insertDocument(db);
        final fileId = await _insertFile(
          db,
          documentId: docId,
          path: r'C:\Library\doc.pdf',
          extension: '.pdf',
        );

        final record = await repo.loadFileRecord(fileId);

        expect(record, isNotNull);
        expect(record!.fileId, fileId);
        expect(record.documentId, docId);
        expect(record.absolutePath, r'C:\Library\doc.pdf');
        expect(record.extension, '.pdf');
        // Column has DB default 'unknown' when not supplied during insert.
        expect(record.fileHealthKey, 'unknown');
      });

      test('returns null after the file is for a different ID', () async {
        final docId = await _insertDocument(db);
        final fileId = await _insertFile(db, documentId: docId);

        final record = await repo.loadFileRecord(fileId + 1000);
        expect(record, isNull);
      });
    });

    // -----------------------------------------------------------------------
    // recordOpenEvent — field correctness
    // -----------------------------------------------------------------------

    group('recordOpenEvent — succeeded', () {
      test('inserts correct event for a file-target success', () async {
        final docId = await _insertDocument(db);
        final fileId = await _insertFile(db, documentId: docId);

        await repo.recordOpenEvent(
          fileId: fileId,
          documentId: docId,
          target: OpenTarget.file,
          resultKey: 'succeeded',
        );

        final events = await db.select(db.fileOpenEvents).get();
        expect(events, hasLength(1));
        final e = events.first;
        expect(e.fileId, fileId);
        expect(e.documentId, docId);
        expect(e.openTargetKey, 'file');
        expect(e.resultKey, 'succeeded');
        expect(e.errorCode, isNull);
        expect(e.messageSafe, isNull);
        expect(e.createdAt, _FixedClock.fixedIso);
      });

      test('inserts correct event for a folder-target success', () async {
        final docId = await _insertDocument(db);
        final fileId = await _insertFile(db, documentId: docId);

        await repo.recordOpenEvent(
          fileId: fileId,
          documentId: docId,
          target: OpenTarget.folder,
          resultKey: 'succeeded',
        );

        final events = await db.select(db.fileOpenEvents).get();
        expect(events, hasLength(1));
        expect(events.first.openTargetKey, 'folder');
      });
    });

    group('recordOpenEvent — blocked', () {
      test('inserts blocked event with stable error code', () async {
        final docId = await _insertDocument(db);
        final fileId = await _insertFile(db, documentId: docId);

        await repo.recordOpenEvent(
          fileId: fileId,
          documentId: docId,
          target: OpenTarget.file,
          resultKey: 'blocked',
          errorCode: 'pathNotFound',
          messageSafe: 'Stored path does not exist on the filesystem.',
        );

        final events = await db.select(db.fileOpenEvents).get();
        expect(events, hasLength(1));
        expect(events.first.resultKey, 'blocked');
        expect(events.first.errorCode, 'pathNotFound');
        expect(
          events.first.messageSafe,
          'Stored path does not exist on the filesystem.',
        );
      });
    });

    group('recordOpenEvent — failed', () {
      test('inserts failed event with stable error code', () async {
        final docId = await _insertDocument(db);
        final fileId = await _insertFile(db, documentId: docId);

        await repo.recordOpenEvent(
          fileId: fileId,
          documentId: docId,
          target: OpenTarget.file,
          resultKey: 'failed',
          errorCode: 'permissionDenied',
          messageSafe: 'Access denied when launching the application.',
        );

        final events = await db.select(db.fileOpenEvents).get();
        expect(events.first.resultKey, 'failed');
        expect(events.first.errorCode, 'permissionDenied');
      });
    });

    group('recordOpenEvent — multiple events accumulate', () {
      test('records multiple events for successive open attempts', () async {
        final docId = await _insertDocument(db);
        final fileId = await _insertFile(db, documentId: docId);

        await repo.recordOpenEvent(
          fileId: fileId,
          documentId: docId,
          target: OpenTarget.file,
          resultKey: 'blocked',
          errorCode: 'pathNotFound',
          messageSafe: 'Stored path does not exist on the filesystem.',
        );
        await repo.recordOpenEvent(
          fileId: fileId,
          documentId: docId,
          target: OpenTarget.file,
          resultKey: 'succeeded',
        );

        final events = await db.select(db.fileOpenEvents).get();
        expect(events, hasLength(2));
        expect(events[0].resultKey, 'blocked');
        expect(events[1].resultKey, 'succeeded');
      });
    });

    // -----------------------------------------------------------------------
    // Immutability: documents and document_files rows unchanged after events
    // -----------------------------------------------------------------------

    group('immutability — no side effects on documents or files', () {
      test('document row unchanged after recording a success event', () async {
        final docId = await _insertDocument(db);
        final fileId = await _insertFile(db, documentId: docId);

        final docBefore = await (db.select(
          db.documents,
        )..where((d) => d.id.equals(docId))).getSingle();

        await repo.recordOpenEvent(
          fileId: fileId,
          documentId: docId,
          target: OpenTarget.file,
          resultKey: 'succeeded',
        );

        final docAfter = await (db.select(
          db.documents,
        )..where((d) => d.id.equals(docId))).getSingle();

        expect(docAfter.workflowStatusKey, docBefore.workflowStatusKey);
        expect(docAfter.updatedAt, docBefore.updatedAt);
        expect(docAfter.classifiedAt, docBefore.classifiedAt);
        expect(docAfter.copiedToLibraryAt, docBefore.copiedToLibraryAt);
        expect(docAfter.title, docBefore.title);
      });

      test(
        'document_files row unchanged after recording a blocked event',
        () async {
          final docId = await _insertDocument(db);
          final fileId = await _insertFile(db, documentId: docId);

          final fileBefore = await (db.select(
            db.documentFiles,
          )..where((f) => f.id.equals(fileId))).getSingle();

          await repo.recordOpenEvent(
            fileId: fileId,
            documentId: docId,
            target: OpenTarget.folder,
            resultKey: 'blocked',
            errorCode: 'unsupportedExtension',
            messageSafe: 'File extension is not in the allowed list.',
          );

          final fileAfter = await (db.select(
            db.documentFiles,
          )..where((f) => f.id.equals(fileId))).getSingle();

          expect(fileAfter.absolutePath, fileBefore.absolutePath);
          expect(fileAfter.fileHealthKey, fileBefore.fileHealthKey);
          expect(fileAfter.fileRoleKey, fileBefore.fileRoleKey);
          expect(fileAfter.updatedAt, fileBefore.updatedAt);
        },
      );

      test('document row unchanged after recording a failed event', () async {
        final docId = await _insertDocument(db);
        final fileId = await _insertFile(db, documentId: docId);

        final docBefore = await (db.select(
          db.documents,
        )..where((d) => d.id.equals(docId))).getSingle();

        await repo.recordOpenEvent(
          fileId: fileId,
          documentId: docId,
          target: OpenTarget.file,
          resultKey: 'failed',
          errorCode: 'osLaunchFailed',
          messageSafe: 'Failed to launch the associated application.',
        );

        final docAfter = await (db.select(
          db.documents,
        )..where((d) => d.id.equals(docId))).getSingle();

        expect(docAfter.workflowStatusKey, docBefore.workflowStatusKey);
        expect(docAfter.updatedAt, docBefore.updatedAt);
      });
    });

    // -----------------------------------------------------------------------
    // FK constraint: unknown fileId cannot be recorded (by design)
    // -----------------------------------------------------------------------

    test(
      'recording event for unknown fileId throws due to FK constraint',
      () async {
        // The file_open_events.file_id FK to document_files.id prevents
        // inserting events for non-existent file IDs. The use case's _tryRecord
        // swallows this error; here we confirm the constraint is active.
        await expectLater(
          repo.recordOpenEvent(
            fileId: 9999,
            documentId: null,
            target: OpenTarget.file,
            resultKey: 'blocked',
            errorCode: 'fileRecordNotFound',
            messageSafe: 'File record not found in database.',
          ),
          throwsA(anything),
        );

        // No event was persisted.
        final events = await db.select(db.fileOpenEvents).get();
        expect(events, isEmpty);
      },
    );
  });
}
