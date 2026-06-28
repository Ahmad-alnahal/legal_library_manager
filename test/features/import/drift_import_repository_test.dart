// test/features/import/drift_import_repository_test.dart

import 'package:drift/drift.dart' show Value;
import 'package:legal_library_manager/features/import/domain/entities/import_batch_report.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/database/seeding/reference_seeder.dart';
import 'package:legal_library_manager/features/import/data/repositories/drift_import_repository.dart';
import 'package:legal_library_manager/features/import/domain/entities/import_error.dart';
import 'package:legal_library_manager/features/import/domain/entities/import_file_result.dart';
import 'package:legal_library_manager/features/import/domain/entities/pdf_health_result.dart';
import 'package:legal_library_manager/features/import/domain/entities/prepared_source_file.dart';
import 'package:sqlite3/common.dart';

void main() {
  late AppDatabase db;
  late DriftImportRepository repo;
  final DateTime now = DateTime.utc(2026, 6, 8, 12);

  setUp(() async {
    db = AppDatabase.inMemory();
    await ReferenceSeeder(db).seedAll();
    repo = DriftImportRepository(db);
  });

  tearDown(() => db.close());

  PreparedSourceFile prepared({
    required String path,
    required String sha,
    String name = 'a.pdf',
    int size = 1234,
    int? pages = 1,
    PdfHealthStatus health = PdfHealthStatus.healthy,
  }) => PreparedSourceFile(
    canonicalPath: path,
    displayName: name,
    extension: '.pdf',
    sizeBytes: size,
    sha256: sha,
    health: health,
    mimeType: 'application/pdf',
    pageCount: pages,
  );

  const String shaA =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const String shaB =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

  Future<List<DocumentFile>> allFiles() => db.select(db.documentFiles).get();

  test(
    'new SHA-256 creates one document and one read-only source row',
    () async {
      final r = await repo.persistHashedFile(
        prepared(path: r'C:\src\a.pdf', sha: shaA),
        operationId: 'op1',
        now: now,
      );

      expect(r.outcome, ImportFileOutcome.importedNew);
      final docs = await db.select(db.documents).get();
      expect(docs.length, 1);
      expect(docs.single.documentCode, isNull); // no code assigned at import.

      final files = await allFiles();
      expect(files.length, 1);
      final f = files.single;
      expect(f.fileRoleKey, 'source_original');
      expect(f.isReadOnlySource, isTrue);
      expect(f.sha256Hash, shaA);
      expect(f.fileName, 'a.pdf');
      expect(f.extension, '.pdf');
      expect(f.fileHealthKey, 'healthy');
      expect(f.pageCount, 1);
      expect(f.mimeType, 'application/pdf');

      // No managed copy populated.
      expect(files.where((x) => x.fileRoleKey == 'managed_copy'), isEmpty);
    },
  );

  test(
    'same absolute path imported twice => already_imported, no new row',
    () async {
      await repo.persistHashedFile(
        prepared(path: r'C:\src\a.pdf', sha: shaA),
        operationId: 'op1',
        now: now,
      );
      final second = await repo.persistHashedFile(
        prepared(path: r'C:\src\a.pdf', sha: shaA),
        operationId: 'op2',
        now: now,
      );

      expect(second.outcome, ImportFileOutcome.alreadyImported);
      expect((await allFiles()).length, 1);
      expect((await db.select(db.documents).get()).length, 1);

      // Last-checked metadata was updated.
      final f = (await allFiles()).single;
      expect(f.existsLastChecked, isTrue);
      expect(f.lastCheckedAt, isNotNull);

      // An existence_checked event was recorded.
      final events = await db.select(db.fileEvents).get();
      expect(events.any((e) => e.eventTypeKey == 'existence_checked'), isTrue);
    },
  );

  test(
    'same Windows path with different casing is the same identity',
    () async {
      await repo.persistHashedFile(
        prepared(path: r'C:\Src\A.pdf', sha: shaA),
        operationId: 'op1',
        now: now,
      );
      final second = await repo.persistHashedFile(
        prepared(path: r'c:\src\a.pdf', sha: shaA),
        operationId: 'op2',
        now: now,
      );
      expect(second.outcome, ImportFileOutcome.alreadyImported);
      expect((await allFiles()).length, 1);
    },
  );

  test('existing SHA at a different path attaches as duplicate_path', () async {
    final first = await repo.persistHashedFile(
      prepared(path: r'C:\src\a.pdf', sha: shaA),
      operationId: 'op1',
      now: now,
    );
    final second = await repo.persistHashedFile(
      prepared(path: r'C:\other\copy.pdf', sha: shaA, name: 'copy.pdf'),
      operationId: 'op2',
      now: now,
    );

    expect(second.outcome, ImportFileOutcome.importedDuplicatePath);
    // Attached to the SAME logical document.
    expect(second.documentId, first.documentId);
    // Two physical files, one document.
    expect((await allFiles()).length, 2);
    expect((await db.select(db.documents).get()).length, 1);
  });

  test('duplicate group contains every matching physical file', () async {
    await repo.persistHashedFile(
      prepared(path: r'C:\src\a.pdf', sha: shaA),
      operationId: 'op1',
      now: now,
    );
    await repo.persistHashedFile(
      prepared(path: r'C:\src\b.pdf', sha: shaA, name: 'b.pdf'),
      operationId: 'op2',
      now: now,
    );
    await repo.persistHashedFile(
      prepared(path: r'C:\src\c.pdf', sha: shaA, name: 'c.pdf'),
      operationId: 'op3',
      now: now,
    );

    final groups = await db.select(db.duplicateGroups).get();
    expect(groups.length, 1);
    expect(groups.single.sha256Hash, shaA);

    final members = await db.select(db.duplicateGroupMembers).get();
    final memberFileIds = members.map((m) => m.fileId).toSet();
    final allFileIds = (await allFiles()).map((f) => f.id).toSet();
    expect(memberFileIds, allFileIds); // all three physical files are members.
  });

  test('a different SHA never joins another hash group', () async {
    await repo.persistHashedFile(
      prepared(path: r'C:\src\a.pdf', sha: shaA),
      operationId: 'op1',
      now: now,
    );
    final other = await repo.persistHashedFile(
      prepared(path: r'C:\src\b.pdf', sha: shaB, name: 'b.pdf'),
      operationId: 'op2',
      now: now,
    );
    expect(other.outcome, ImportFileOutcome.importedNew);
    expect((await db.select(db.duplicateGroups).get()), isEmpty);
  });

  test(
    'hash failure retains a source row, marks unreadable, joins no group',
    () async {
      final r = await repo.persistFailedFile(
        const FailedSourceFile(
          canonicalPath: r'C:\src\broken.pdf',
          displayName: 'broken.pdf',
          extension: '.pdf',
          sizeBytes: 0,
          health: PdfHealthStatus.unreadable,
          errorCode: 'hash_failed',
          safeMessage: 'read failed',
        ),
        outcome: ImportFileOutcome.hashFailed,
        operationId: 'op1',
        now: now,
      );

      expect(r.outcome, ImportFileOutcome.hashFailed);
      final files = await allFiles();
      expect(files.length, 1);
      expect(files.single.sha256Hash, isNull);
      expect(files.single.fileHealthKey, 'unreadable');
      // Not added to any duplicate group.
      expect((await db.select(db.duplicateGroups).get()), isEmpty);
      expect((await db.select(db.duplicateGroupMembers).get()), isEmpty);

      // A safe failure event with no contents.
      final event = (await db.select(db.fileEvents).get()).firstWhere(
        (e) => e.eventTypeKey == 'hash_failed',
      );
      expect(event.resultKey, 'failed');
      expect(event.errorCode, 'hash_failed');
      expect(event.messageSafe, 'read failed');
    },
  );

  test('one failed file does not abort subsequent files', () async {
    await repo.persistFailedFile(
      const FailedSourceFile(
        canonicalPath: r'C:\src\broken.pdf',
        displayName: 'broken.pdf',
        extension: '.pdf',
        sizeBytes: 0,
        health: PdfHealthStatus.unreadable,
      ),
      outcome: ImportFileOutcome.unreadable,
      operationId: 'op1',
      now: now,
    );
    final ok = await repo.persistHashedFile(
      prepared(path: r'C:\src\good.pdf', sha: shaA, name: 'good.pdf'),
      operationId: 'op2',
      now: now,
    );
    expect(ok.outcome, ImportFileOutcome.importedNew);
    expect((await allFiles()).length, 2);
  });

  test('a single-file persistence failure rolls back that file only', () async {
    // First file imports successfully.
    await repo.persistHashedFile(
      prepared(path: r'C:\src\a.pdf', sha: shaA),
      operationId: 'op1',
      now: now,
    );

    // Second file forces a CHECK violation (negative size) mid-transaction
    // AFTER its document row would have been inserted.
    await expectLater(
      repo.persistHashedFile(
        prepared(path: r'C:\src\bad.pdf', sha: shaB, size: -1, name: 'bad.pdf'),
        operationId: 'op2',
        now: now,
      ),
      throwsA(isA<SqliteException>()),
    );

    // Only the first file's rows survive; the failed file rolled back fully.
    expect((await db.select(db.documents).get()).length, 1);
    expect((await allFiles()).length, 1);
    expect((await allFiles()).single.fileName, 'a.pdf');
  });

  test('fileless outcomes record a safe event and no file row', () async {
    final r = await repo.recordFilelessOutcome(
      outcome: ImportFileOutcome.scanFailed,
      sourcePath: r'C:\src\locked',
      operationId: 'op1',
      now: now,
      safeMessage: 'permission denied',
    );
    expect(r.outcome, ImportFileOutcome.scanFailed);
    expect(r.fileId, isNull);
    expect((await allFiles()), isEmpty);
    final event = (await db.select(db.fileEvents).get()).single;
    expect(event.resultKey, 'failed');
    expect(event.errorCode, 'scan_failed');
  });

  group('batch primitives', () {
    test(
      'createBatch produces a unique stable code in running state',
      () async {
        final b1 = await repo.createBatch(
          sourceFolder: r'C:\src',
          recursive: true,
          now: now,
        );
        final b2 = await repo.createBatch(
          sourceFolder: r'C:\src',
          recursive: false,
          now: now,
        );
        expect(b1.batchCode, isNot(b2.batchCode));
        final row = await (db.select(
          db.importBatches,
        )..where((b) => b.id.equals(b1.id))).getSingle();
        expect(row.statusKey, 'running');
      },
    );

    test('attach result rows and complete the batch', () async {
      final batch = await repo.createBatch(
        sourceFolder: r'C:\src',
        recursive: true,
        now: now,
      );
      final r = await repo.persistHashedFile(
        prepared(path: r'C:\src\a.pdf', sha: shaA),
        operationId: 'op1',
        now: now,
        batchId: batch.id,
      );

      final batchFiles = await db.select(db.importBatchFiles).get();
      expect(batchFiles.length, 1);
      expect(batchFiles.single.fileId, r.fileId);
      expect(batchFiles.single.resultKey, 'imported_new');

      await repo.completeBatch(
        batch.id,
        discoveredCount: 1,
        importedCount: 1,
        duplicateCount: 0,
        failedCount: 0,
        pairedCount: 0,
        now: now,
      );
      final row = await (db.select(
        db.importBatches,
      )..where((b) => b.id.equals(batch.id))).getSingle();
      expect(row.statusKey, 'completed');
      expect(row.importedCount, 1);
      expect(row.completedAt, isNotNull);
    });

    test('fail and cancel set terminal statuses', () async {
      final b1 = await repo.createBatch(
        sourceFolder: r'C:\s',
        recursive: true,
        now: now,
      );
      await repo.failBatch(b1.id, now: now);
      expect(
        (await (db.select(
          db.importBatches,
        )..where((b) => b.id.equals(b1.id))).getSingle()).statusKey,
        'failed',
      );

      final b2 = await repo.createBatch(
        sourceFolder: r'C:\s',
        recursive: true,
        now: now,
      );
      await repo.cancelBatch(b2.id, now: now);
      expect(
        (await (db.select(
          db.importBatches,
        )..where((b) => b.id.equals(b2.id))).getSingle()).statusKey,
        'cancelled',
      );
    });
  });

  test('all stored timestamps are UTC ISO-8601', () async {
    await repo.persistHashedFile(
      prepared(path: r'C:\src\a.pdf', sha: shaA),
      operationId: 'op1',
      now: now,
    );
    final f = (await allFiles()).single;
    expect(f.createdAt, now.toIso8601String());
    expect(f.createdAt.endsWith('Z'), isTrue);
  });

  group('retry of failed existing paths', () {
    test('a failed file is retried in place into imported_new', () async {
      await repo.persistFailedFile(
        const FailedSourceFile(
          canonicalPath: r'C:\src\f.pdf',
          displayName: 'f.pdf',
          extension: '.pdf',
          sizeBytes: 0,
          health: PdfHealthStatus.unreadable,
          errorCode: 'hash_failed',
        ),
        outcome: ImportFileOutcome.hashFailed,
        operationId: 'op1',
        now: now,
      );
      final before = (await allFiles()).single;
      expect(before.sha256Hash, isNull);

      final retry = await repo.persistHashedFile(
        prepared(path: r'C:\src\f.pdf', sha: shaA, name: 'f.pdf', size: 999),
        operationId: 'op2',
        now: now,
      );

      expect(retry.outcome, ImportFileOutcome.importedNew);
      // No second physical row for the same path.
      final files = await allFiles();
      expect(files.length, 1);
      expect(files.single.id, before.id);
      expect(files.single.sha256Hash, shaA);
      expect(files.single.fileHealthKey, 'healthy');
      expect(files.single.fileSizeBytes, 999);
      expect(files.single.pageCount, 1);
    });

    test(
      'a same-path completed file is NOT retried (already_imported)',
      () async {
        await repo.persistHashedFile(
          prepared(path: r'C:\src\g.pdf', sha: shaA, name: 'g.pdf'),
          operationId: 'op1',
          now: now,
        );
        final again = await repo.persistHashedFile(
          prepared(path: r'C:\src\g.pdf', sha: shaB, name: 'g.pdf'),
          operationId: 'op2',
          now: now,
        );
        expect(again.outcome, ImportFileOutcome.alreadyImported);
        // Hash is preserved (not overwritten by a re-scan).
        expect((await allFiles()).single.sha256Hash, shaA);
      },
    );

    test(
      'failed retry into a duplicate merges onto one canonical document',
      () async {
        // A healthy file with shaA at path1.
        final good = await repo.persistHashedFile(
          prepared(path: r'C:\src\a.pdf', sha: shaA),
          operationId: 'op1',
          now: now,
        );
        // A failed retain at path2 (gets its own temporary placeholder document).
        final failed = await repo.persistFailedFile(
          const FailedSourceFile(
            canonicalPath: r'C:\src\b.pdf',
            displayName: 'b.pdf',
            extension: '.pdf',
            sizeBytes: 0,
            health: PdfHealthStatus.unreadable,
          ),
          outcome: ImportFileOutcome.unreadable,
          operationId: 'op2',
          now: now,
        );
        expect(failed.documentId, isNot(good.documentId));

        // Retry path2: it now hashes to shaA -> duplicate of path1.
        final retry = await repo.persistHashedFile(
          prepared(path: r'C:\src\b.pdf', sha: shaA, name: 'b.pdf'),
          operationId: 'op3',
          now: now,
        );
        expect(retry.outcome, ImportFileOutcome.importedDuplicatePath);
        expect(retry.error, isNull);

        // Finalized identity: both physical files now share ONE logical document
        // (the canonical lowest-id document), and the empty placeholder is gone.
        expect(retry.documentId, good.documentId);
        expect((await db.select(db.documents).get()).length, 1);
        final files = await allFiles();
        expect(files.length, 2);
        expect(files.every((f) => f.documentId == good.documentId), isTrue);

        // One duplicate group with both physical files as members.
        final groups = await db.select(db.duplicateGroups).get();
        expect(groups.length, 1);
        final memberIds = (await db.select(db.duplicateGroupMembers).get())
            .map((m) => m.fileId)
            .toSet();
        expect(memberIds, {good.fileId, failed.fileId});
      },
    );

    test(
      'placeholder cleanup cannot remove a document with business metadata',
      () async {
        final good = await repo.persistHashedFile(
          prepared(path: r'C:\src\a.pdf', sha: shaA),
          operationId: 'op1',
          now: now,
        );
        final failed = await repo.persistFailedFile(
          const FailedSourceFile(
            canonicalPath: r'C:\src\b.pdf',
            displayName: 'b.pdf',
            extension: '.pdf',
            sizeBytes: 0,
            health: PdfHealthStatus.unreadable,
          ),
          outcome: ImportFileOutcome.unreadable,
          operationId: 'op2',
          now: now,
        );

        // Simulate meaningful business metadata on the placeholder document
        // (e.g. a title entered before retry).
        await (db.update(
          db.documents,
        )..where((d) => d.id.equals(failed.documentId!))).write(
          const DocumentsCompanion(title: Value('Hand-entered title')),
        );

        final retry = await repo.persistHashedFile(
          prepared(path: r'C:\src\b.pdf', sha: shaA, name: 'b.pdf'),
          operationId: 'op3',
          now: now,
        );

        // Identity is still satisfied: the physical file moved to canonical.
        expect(retry.outcome, ImportFileOutcome.importedDuplicatePath);
        expect(retry.documentId, good.documentId);
        final files = await allFiles();
        expect(files.every((f) => f.documentId == good.documentId), isTrue);

        // The meaningful placeholder document is preserved (NOT deleted) and a
        // structured conflict is reported.
        expect(retry.error, isNotNull);
        expect(retry.error!.code, ImportErrorCode.duplicateIdentityConflict);
        final placeholder = await (db.select(
          db.documents,
        )..where((d) => d.id.equals(failed.documentId!))).getSingleOrNull();
        expect(placeholder, isNotNull);
        expect(placeholder!.title, 'Hand-entered title');
      },
    );

    Future<void> expectPlaceholderPreservedFor(
      DocumentsCompanion change,
    ) async {
      final good = await repo.persistHashedFile(
        prepared(path: r'C:\src\a.pdf', sha: shaA),
        operationId: 'op1',
        now: now,
      );
      final failed = await repo.persistFailedFile(
        const FailedSourceFile(
          canonicalPath: r'C:\src\b.pdf',
          displayName: 'b.pdf',
          extension: '.pdf',
          sizeBytes: 0,
          health: PdfHealthStatus.unreadable,
        ),
        outcome: ImportFileOutcome.unreadable,
        operationId: 'op2',
        now: now,
      );

      // Only a single reference value differs from its schema default.
      await (db.update(
        db.documents,
      )..where((d) => d.id.equals(failed.documentId!))).write(change);

      final retry = await repo.persistHashedFile(
        prepared(path: r'C:\src\b.pdf', sha: shaA, name: 'b.pdf'),
        operationId: 'op3',
        now: now,
      );

      // Physical file still moves to the canonical document (identity holds).
      expect(retry.outcome, ImportFileOutcome.importedDuplicatePath);
      expect(retry.documentId, good.documentId);
      expect(
        (await allFiles()).every((f) => f.documentId == good.documentId),
        isTrue,
      );
      // The meaningful placeholder is preserved and a conflict is reported.
      expect(retry.error?.code, ImportErrorCode.duplicateIdentityConflict);
      final placeholder = await (db.select(
        db.documents,
      )..where((d) => d.id.equals(failed.documentId!))).getSingleOrNull();
      expect(placeholder, isNotNull);
    }

    test('placeholder with a non-default trust level is preserved', () async {
      await expectPlaceholderPreservedFor(
        const DocumentsCompanion(trustLevelKey: Value('trusted')),
      );
    });

    test('placeholder with non-default usage rights is preserved', () async {
      await expectPlaceholderPreservedFor(
        const DocumentsCompanion(usageRightsKey: Value('publishable')),
      );
    });

    test(
      'placeholder with non-default metadata quality is preserved',
      () async {
        await expectPlaceholderPreservedFor(
          const DocumentsCompanion(metadataQualityKey: Value('high')),
        );
      },
    );

    test('retry within the same batch upserts the result row', () async {
      final batch = await repo.createBatch(
        sourceFolder: r'C:\src',
        recursive: true,
        now: now,
      );
      await repo.persistFailedFile(
        const FailedSourceFile(
          canonicalPath: r'C:\src\f.pdf',
          displayName: 'f.pdf',
          extension: '.pdf',
          sizeBytes: 0,
          health: PdfHealthStatus.unreadable,
        ),
        outcome: ImportFileOutcome.hashFailed,
        operationId: 'op1',
        now: now,
        batchId: batch.id,
      );

      // Retrying the same file in the same batch must not throw a composite-PK
      // violation; it upserts the existing result row.
      final retry = await repo.persistHashedFile(
        prepared(path: r'C:\src\f.pdf', sha: shaA, name: 'f.pdf'),
        operationId: 'op2',
        now: now,
        batchId: batch.id,
      );
      expect(retry.outcome, ImportFileOutcome.importedNew);

      final batchFiles = await db.select(db.importBatchFiles).get();
      expect(batchFiles.length, 1);
      expect(batchFiles.single.resultKey, 'imported_new');
    });
  });

  group('collision-safe stable codes', () {
    Future<void> makeDupGroup(String sha, String tag) async {
      // Two files with the same hash form a duplicate group.
      await repo.persistHashedFile(
        prepared(path: 'C:\\src\\${tag}1.pdf', sha: sha, name: '${tag}1.pdf'),
        operationId: '$tag-1',
        now: now,
      );
      await repo.persistHashedFile(
        prepared(path: 'C:\\src\\${tag}2.pdf', sha: sha, name: '${tag}2.pdf'),
        operationId: '$tag-2',
        now: now,
      );
    }

    test('batch code is not reused after deleting the highest', () async {
      await repo.createBatch(sourceFolder: r'C:\s', recursive: true, now: now);
      await repo.createBatch(sourceFolder: r'C:\s', recursive: true, now: now);
      final b3 = await repo.createBatch(
        sourceFolder: r'C:\s',
        recursive: true,
        now: now,
      );
      expect(b3.batchCode, 'IMPORT-0000003');

      // Delete the HIGHEST-numbered batch.
      await (db.delete(
        db.importBatches,
      )..where((b) => b.id.equals(b3.id))).go();

      // A durable allocator must NOT reuse 0000003.
      final b4 = await repo.createBatch(
        sourceFolder: r'C:\s',
        recursive: true,
        now: now,
      );
      expect(b4.batchCode, 'IMPORT-0000004');
    });

    test('batch code keeps climbing after deleting lower codes', () async {
      final b1 = await repo.createBatch(
        sourceFolder: r'C:\s',
        recursive: true,
        now: now,
      );
      final b2 = await repo.createBatch(
        sourceFolder: r'C:\s',
        recursive: true,
        now: now,
      );
      await repo.createBatch(sourceFolder: r'C:\s', recursive: true, now: now);

      await (db.delete(
        db.importBatches,
      )..where((b) => b.id.isIn([b1.id, b2.id]))).go();

      final next = await repo.createBatch(
        sourceFolder: r'C:\s',
        recursive: true,
        now: now,
      );
      expect(next.batchCode, 'IMPORT-0000004');
    });

    test('concurrent batch creation yields unique codes, no throw', () async {
      final results = await Future.wait(
        List.generate(
          10,
          (_) => repo.createBatch(
            sourceFolder: r'C:\s',
            recursive: true,
            now: now,
          ),
        ),
      );
      final codes = results.map((r) => r.batchCode).toList();
      expect(codes.toSet().length, 10); // all unique.
      final stored = (await db.select(db.importBatches).get())
          .map((b) => b.batchCode)
          .toList();
      expect(stored.toSet().length, stored.length);
    });

    test(
      'duplicate-group code is not reused after deleting the highest',
      () async {
        await makeDupGroup(shaA, 'a');
        await makeDupGroup(shaB, 'b');
        final highest = (await db.select(db.duplicateGroups).get()).firstWhere(
          (g) => g.groupCode == 'DUP-GROUP-00002',
        );

        // Delete the HIGHEST group (cascades its members).
        await (db.delete(
          db.duplicateGroups,
        )..where((g) => g.id.equals(highest.id))).go();

        final String shaC = 'c' * 64;
        await makeDupGroup(shaC, 'c');
        final codes = (await db.select(db.duplicateGroups).get())
            .map((g) => g.groupCode)
            .toList();
        // Must allocate 00003, never reuse the deleted 00002.
        expect(codes, contains('DUP-GROUP-00003'));
        expect(codes, isNot(contains('DUP-GROUP-00002')));
        expect(codes.toSet().length, codes.length);
      },
    );

    test(
      'batch allocator bootstraps from existing codes (no counter)',
      () async {
        // Simulate a pre-allocator database: an existing batch code, no counter.
        await db
            .into(db.importBatches)
            .insert(
              ImportBatchesCompanion.insert(
                batchCode: 'IMPORT-0000005',
                sourceFolder: r'C:\s',
                recursiveScan: true,
                statusKey: 'completed',
                startedAt: now.toIso8601String(),
              ),
            );
        expect(
          await (db.select(
            db.settings,
          )..where((s) => s.key.equals('seq.import_batch'))).getSingleOrNull(),
          isNull,
        );

        final next = await repo.createBatch(
          sourceFolder: r'C:\s',
          recursive: true,
          now: now,
        );
        expect(next.batchCode, 'IMPORT-0000006');
      },
    );

    test(
      'group allocator bootstraps from existing codes (no counter)',
      () async {
        // Pre-existing duplicate group code with no allocator counter.
        await db
            .into(db.duplicateGroups)
            .insert(
              DuplicateGroupsCompanion.insert(
                groupCode: 'DUP-GROUP-00005',
                sha256Hash: 'f' * 64,
                createdAt: now.toIso8601String(),
                updatedAt: now.toIso8601String(),
              ),
            );
        expect(
          await (db.select(db.settings)
                ..where((s) => s.key.equals('seq.duplicate_group')))
              .getSingleOrNull(),
          isNull,
        );

        // A fresh duplicate hash triggers allocation of the next group code.
        await makeDupGroup(shaA, 'a');
        final codes = (await db.select(db.duplicateGroups).get())
            .map((g) => g.groupCode)
            .toList();
        expect(codes, contains('DUP-GROUP-00006'));
        expect(codes, isNot(contains('DUP-GROUP-00005-dup')));
      },
    );

    test('a malformed counter fails safely without reusing codes', () async {
      final first = await repo.createBatch(
        sourceFolder: r'C:\s',
        recursive: true,
        now: now,
      );
      expect(first.batchCode, 'IMPORT-0000001');

      // Corrupt the persisted counter.
      await db
          .into(db.settings)
          .insertOnConflictUpdate(
            SettingsCompanion.insert(
              key: 'seq.import_batch',
              value: 'not-a-number',
              updatedAt: now.toIso8601String(),
            ),
          );

      // Allocation must throw rather than silently reset to zero (which would
      // reuse IMPORT-0000001).
      await expectLater(
        repo.createBatch(sourceFolder: r'C:\s', recursive: true, now: now),
        throwsA(isA<StateError>()),
      );

      // No new/duplicate batch row was created.
      final codes = (await db.select(db.importBatches).get())
          .map((b) => b.batchCode)
          .toList();
      expect(codes, ['IMPORT-0000001']);
    });
  });

  group('getRecentBatches', () {
    Future<ImportBatchRef> insertBatch(
      String folder,
      ImportBatchStatus status,
      String startedAt, {
      String? completedAt,
    }) async {
      final ref = await repo.createBatch(
        sourceFolder: folder,
        recursive: false,
        now: DateTime.parse(startedAt),
      );
      if (status != ImportBatchStatus.running) {
        await repo.updateBatchProgress(ref.id, status: status);
        if (completedAt != null) {
          await (db.update(db.importBatches)..where((b) => b.id.equals(ref.id)))
              .write(ImportBatchesCompanion(completedAt: Value(completedAt)));
        }
      }
      return ref;
    }

    test('returns empty list when no batches exist', () async {
      final result = await repo.getRecentBatches();
      expect(result, isEmpty);
    });

    test('returns batches ordered newest-first by startedAt', () async {
      await insertBatch(
        r'C:\folderA',
        ImportBatchStatus.completed,
        '2026-06-01T10:00:00.000Z',
        completedAt: '2026-06-01T10:05:00.000Z',
      );
      await insertBatch(
        r'C:\folderB',
        ImportBatchStatus.failed,
        '2026-06-02T10:00:00.000Z',
        completedAt: '2026-06-02T10:01:00.000Z',
      );
      await insertBatch(
        r'C:\folderC',
        ImportBatchStatus.interrupted,
        '2026-06-03T10:00:00.000Z',
      );

      final result = await repo.getRecentBatches();

      expect(result, hasLength(3));
      expect(result[0].sourceFolder, r'C:\folderC');
      expect(result[1].sourceFolder, r'C:\folderB');
      expect(result[2].sourceFolder, r'C:\folderA');
    });

    test('respects the limit parameter', () async {
      for (var i = 1; i <= 5; i++) {
        await insertBatch(
          r'C:\folder',
          ImportBatchStatus.completed,
          '2026-06-0${i}T10:00:00.000Z',
        );
      }

      final result = await repo.getRecentBatches(limit: 3);

      expect(result, hasLength(3));
    });

    test('maps status keys to ImportBatchStatus correctly', () async {
      await insertBatch(
        r'C:\src',
        ImportBatchStatus.cancelled,
        '2026-06-01T10:00:00.000Z',
      );

      final result = await repo.getRecentBatches();

      expect(result.single.status, ImportBatchStatus.cancelled);
    });

    test('maps all count fields from the row', () async {
      final ref = await repo.createBatch(
        sourceFolder: r'C:\src',
        recursive: true,
        now: DateTime.utc(2026, 6, 1, 10),
      );
      await repo.completeBatch(
        ref.id,
        discoveredCount: 10,
        importedCount: 7,
        duplicateCount: 2,
        failedCount: 1,
        pairedCount: 3,
        now: DateTime.utc(2026, 6, 1, 11),
      );

      final result = await repo.getRecentBatches();
      final record = result.single;

      expect(record.discoveredCount, 10);
      expect(record.importedCount, 7);
      expect(record.duplicateCount, 2);
      expect(record.failedCount, 1);
      expect(record.pairedCount, 3);
      expect(record.completedAt, isNotNull);
    });
  });
}
