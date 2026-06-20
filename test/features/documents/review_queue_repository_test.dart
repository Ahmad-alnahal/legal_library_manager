import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/database/seeding/reference_seeder.dart';
import 'package:legal_library_manager/features/documents/data/repositories/drift_review_queue_repository.dart';
import 'package:legal_library_manager/features/documents/domain/entities/review_queue_query.dart';

void main() {
  group('DriftReviewQueueRepository', () {
    late AppDatabase db;
    late DriftReviewQueueRepository repository;

    const now = '2026-06-09T12:00:00.000Z';
    var fileSeq = 0;

    setUp(() async {
      db = AppDatabase.inMemory();
      await ReferenceSeeder(db).seedAll();
      repository = DriftReviewQueueRepository(db);
      fileSeq = 0;
    });

    tearDown(() => db.close());

    /// Attaches a source file with the given [health] to [documentId]. Each file
    /// gets a unique absolute path so the unique-path constraint never trips.
    Future<void> addFile(int documentId, String health) async {
      final n = fileSeq++;
      await db
          .into(db.documentFiles)
          .insert(
            DocumentFilesCompanion.insert(
              documentId: documentId,
              fileRoleKey: 'source_original',
              fileName: 'file_$n.pdf',
              absolutePath: 'C:\\src\\file_$n.pdf',
              extension: '.pdf',
              fileSizeBytes: 100,
              fileHealthKey: Value(health),
              createdAt: now,
              updatedAt: now,
            ),
          );
    }

    /// Inserts a document and, by default, one `healthy` source file so it is
    /// eligible for the review queue. Pass [fileHealths] to control the attached
    /// files (an empty list creates a document with no files).
    Future<int> addDocument({
      required String status,
      String? title,
      String updatedAt = now,
      List<String> fileHealths = const ['healthy'],
    }) async {
      final id = await db
          .into(db.documents)
          .insert(
            DocumentsCompanion.insert(
              title: Value(title),
              workflowStatusKey: Value(status),
              createdAt: now,
              updatedAt: updatedAt,
            ),
          );
      for (final h in fileHealths) {
        await addFile(id, h);
      }
      return id;
    }

    test(
      'default queue includes imported, needs_review, in_progress',
      () async {
        final imported = await addDocument(status: 'imported');
        final needsReview = await addDocument(status: 'needs_review');
        final inProgress = await addDocument(status: 'in_progress');
        await addDocument(status: 'classified');
        await addDocument(status: 'copied_to_library');

        final page = await repository.getQueue(const ReviewQueueQuery());

        expect(page.totalCount, 3);
        expect(page.items.map((e) => e.id), [
          imported,
          needsReview,
          inProgress,
        ]);
        expect(page.items.map((e) => e.workflowStatusKey), [
          'imported',
          'needs_review',
          'in_progress',
        ]);
      },
    );

    test('classified scope returns classified and copied documents', () async {
      await addDocument(status: 'imported');
      final classified = await addDocument(status: 'classified');
      final copied = await addDocument(status: 'copied_to_library');

      final page = await repository.getQueue(
        const ReviewQueueQuery(scope: ReviewQueueScope.classified),
      );

      expect(page.totalCount, 2);
      expect(page.items.map((item) => item.id), [classified, copied]);
      expect(page.items.map((item) => item.workflowStatusKey), [
        'classified',
        'copied_to_library',
      ]);
    });

    test('pagination is stable and deterministic by id', () async {
      final ids = <int>[];
      for (var i = 0; i < 7; i++) {
        ids.add(await addDocument(status: 'imported', title: 'وثيقة $i'));
      }

      final first = await repository.getQueue(const ReviewQueueQuery(limit: 3));
      final second = await repository.getQueue(
        const ReviewQueueQuery(offset: 3, limit: 3),
      );
      final third = await repository.getQueue(
        const ReviewQueueQuery(offset: 6, limit: 3),
      );

      expect(first.totalCount, 7);
      expect(first.hasMore, isTrue);
      expect(first.items.map((e) => e.id), ids.sublist(0, 3));
      expect(second.items.map((e) => e.id), ids.sublist(3, 6));
      expect(third.items.map((e) => e.id), ids.sublist(6, 7));
      expect(third.hasMore, isFalse);
    });

    test('source filename and type name are projected', () async {
      final bookTypeId = (await (db.select(
        db.documentTypes,
      )..where((t) => t.key.equals('book'))).getSingle()).id;
      final id = await db
          .into(db.documents)
          .insert(
            DocumentsCompanion.insert(
              documentTypeId: Value(bookTypeId),
              workflowStatusKey: const Value('imported'),
              createdAt: now,
              updatedAt: now,
            ),
          );
      await db
          .into(db.documentFiles)
          .insert(
            DocumentFilesCompanion.insert(
              documentId: id,
              fileRoleKey: 'source_original',
              fileName: 'الأصل.pdf',
              absolutePath: r'C:\src\original.pdf',
              extension: '.pdf',
              fileSizeBytes: 100,
              createdAt: now,
              updatedAt: now,
            ),
          );

      final page = await repository.getQueue(const ReviewQueueQuery());

      expect(page.items.single.sourceFileName, 'الأصل.pdf');
      expect(page.items.single.documentTypeNameAr, 'كتاب');
    });

    group('broken-file eligibility', () {
      test('a document with only broken files is excluded', () async {
        await addDocument(status: 'imported', fileHealths: const ['corrupted']);
        await addDocument(
          status: 'needs_review',
          fileHealths: const ['unreadable'],
        );
        await addDocument(
          status: 'in_progress',
          fileHealths: const ['missing'],
        );
        await addDocument(
          status: 'imported',
          fileHealths: const ['corrupted', 'missing', 'unreadable'],
        );

        final page = await repository.getQueue(const ReviewQueueQuery());

        expect(page.totalCount, 0);
        expect(page.items, isEmpty);
      });

      test('a document with zero files is excluded', () async {
        await addDocument(status: 'imported', fileHealths: const []);

        final page = await repository.getQueue(const ReviewQueueQuery());

        expect(page.totalCount, 0);
        expect(page.items, isEmpty);
      });

      test('healthy and unknown documents are included', () async {
        final healthy = await addDocument(
          status: 'imported',
          fileHealths: const ['healthy'],
        );
        final unknown = await addDocument(
          status: 'in_progress',
          fileHealths: const ['unknown'],
        );

        final page = await repository.getQueue(const ReviewQueueQuery());

        expect(page.totalCount, 2);
        expect(page.items.map((e) => e.id), [healthy, unknown]);
      });

      test(
        'a document with both broken and reviewable files is included',
        () async {
          final mixed = await addDocument(
            status: 'imported',
            fileHealths: const ['corrupted', 'healthy'],
          );

          final page = await repository.getQueue(const ReviewQueueQuery());

          expect(page.totalCount, 1);
          expect(page.items.single.id, mixed);
        },
      );

      test('classified scope also excludes broken-only documents', () async {
        final ok = await addDocument(
          status: 'classified',
          fileHealths: const ['healthy'],
        );
        await addDocument(
          status: 'classified',
          fileHealths: const ['corrupted'],
        );
        await addDocument(status: 'classified', fileHealths: const []);

        final page = await repository.getQueue(
          const ReviewQueueQuery(scope: ReviewQueueScope.classified),
        );

        expect(page.totalCount, 1);
        expect(page.items.single.id, ok);
      });

      test(
        'count and pagination stay accurate when broken docs are interleaved',
        () async {
          final eligible = <int>[];
          for (var i = 0; i < 5; i++) {
            // Interleave an excluded broken-only document between eligible ones.
            eligible.add(
              await addDocument(status: 'imported', title: 'سليم $i'),
            );
            await addDocument(
              status: 'imported',
              title: 'تالف $i',
              fileHealths: const ['corrupted'],
            );
          }

          final first = await repository.getQueue(
            const ReviewQueueQuery(limit: 2),
          );
          final second = await repository.getQueue(
            const ReviewQueueQuery(offset: 2, limit: 2),
          );
          final third = await repository.getQueue(
            const ReviewQueueQuery(offset: 4, limit: 2),
          );

          expect(first.totalCount, 5);
          expect(first.items.map((e) => e.id), eligible.sublist(0, 2));
          expect(second.items.map((e) => e.id), eligible.sublist(2, 4));
          expect(third.items.map((e) => e.id), eligible.sublist(4, 5));
          expect(third.hasMore, isFalse);
        },
      );

      test('broken document/file records are not modified', () async {
        final id = await addDocument(
          status: 'imported',
          fileHealths: const ['corrupted'],
        );

        await repository.getQueue(const ReviewQueueQuery());

        final doc = await (db.select(
          db.documents,
        )..where((d) => d.id.equals(id))).getSingle();
        expect(doc.workflowStatusKey, 'imported');
        final files = await (db.select(
          db.documentFiles,
        )..where((f) => f.documentId.equals(id))).get();
        expect(files.single.fileHealthKey, 'corrupted');
      });
    });

    test('invalid pagination is rejected at runtime', () async {
      await expectLater(
        repository.getQueue(const ReviewQueueQuery(limit: 0)),
        throwsArgumentError,
      );
      await expectLater(
        repository.getQueue(const ReviewQueueQuery(offset: -1)),
        throwsArgumentError,
      );
    });
  });
}
