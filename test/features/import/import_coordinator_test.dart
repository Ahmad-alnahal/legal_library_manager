// test/features/import/import_coordinator_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/database/seeding/reference_seeder.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/features/import/application/import_coordinator.dart';
import 'package:legal_library_manager/features/import/application/import_file_report.dart';
import 'package:legal_library_manager/features/import/application/import_progress.dart';
import 'package:legal_library_manager/features/import/data/repositories/drift_import_repository.dart';
import 'package:legal_library_manager/features/import/domain/entities/folder_validation.dart';
import 'package:legal_library_manager/features/import/domain/entities/import_batch_report.dart';
import 'package:legal_library_manager/features/import/domain/entities/import_error.dart';
import 'package:legal_library_manager/features/import/domain/entities/import_request.dart';
import 'package:legal_library_manager/features/import/domain/entities/pdf_candidate.dart';
import 'package:legal_library_manager/features/import/domain/entities/prepared_source_file.dart';
import 'package:legal_library_manager/features/import/domain/entities/pdf_health_result.dart';
import 'package:legal_library_manager/features/import/domain/entities/protected_roots.dart';
import 'package:legal_library_manager/features/import/domain/services/file_hasher.dart';

import 'support/import_fakes.dart';

void main() {
  late AppDatabase db;
  late DriftImportRepository repo;

  const ProtectedRoots roots = ProtectedRoots(databaseRoot: r'C:\db');
  final ImportRequest request = const ImportRequest(
    sourceFolder: r'C:\src',
    recursive: true,
    protectedRoots: roots,
  );
  const valid = FolderValidationResult.valid(r'C:\src');

  String hex(String c) => c * 64;

  setUp(() async {
    db = AppDatabase.inMemory();
    await ReferenceSeeder(db).seedAll();
    repo = DriftImportRepository(db);
  });

  tearDown(() => db.close());

  ImportCoordinator build({
    required FakePdfScanner scanner,
    required FakeFileHasher hasher,
    FakePdfHealthInspector? inspector,
    FakeFolderValidator? validator,
    IsolateRunner runner = syncRunner,
  }) {
    return ImportCoordinator(
      validator: validator ?? FakeFolderValidator(valid),
      scanner: scanner,
      hasher: hasher,
      inspector: inspector ?? FakePdfHealthInspector(),
      repository: repo,
      clock: const SystemClock(),
      runner: runner,
    );
  }

  test('mixed batch: new, duplicate, already imported, and failed', () async {
    // Pre-import c.pdf so it is "already imported".
    await repo.persistHashedFile(
      PreparedSourceFile(
        canonicalPath: r'C:\src\c.pdf',
        displayName: 'c.pdf',
        extension: '.pdf',
        sizeBytes: 100,
        sha256: hex('c'),
        health: PdfHealthStatus.healthy,
      ),
      operationId: 'seed',
      now: DateTime.utc(2026),
    );

    final scanner = FakePdfScanner(
      PdfScanResult(
        candidates: [
          candidate(r'C:\src\a.pdf'),
          candidate(r'C:\src\b.pdf'),
          candidate(r'C:\src\c.pdf'),
          candidate(r'C:\src\d.pdf'),
        ],
      ),
    );
    final hasher = FakeFileHasher(
      hashes: {
        r'C:\src\a.pdf': hex('a'),
        r'C:\src\b.pdf': hex('a'), // duplicate of a
      },
      failures: {r'C:\src\d.pdf'},
    );

    final report = await build(
      scanner: scanner,
      hasher: hasher,
    ).run(request, cancellation: MutableHashCancellation());

    expect(report.status, ImportBatchStatus.completed);
    expect(report.files.map((f) => f.status).toList(), [
      ImportFileStatus.importedNew, // a
      ImportFileStatus.importedDuplicatePath, // b
      ImportFileStatus.alreadyImported, // c
      ImportFileStatus.hashFailed, // d
    ]);
    expect(report.importedNewCount, 1);
    expect(report.duplicateCount, 1);
    expect(report.alreadyImportedCount, 1);
    expect(report.failedCount, 1);

    // Batch persisted as completed with matching counters.
    final batch = await (db.select(
      db.importBatches,
    )..where((b) => b.id.equals(report.batch!.id))).getSingle();
    expect(batch.statusKey, 'completed');
    expect(batch.discoveredCount, 4);
    expect(batch.failedCount, 1);
  });

  test('partial success does not fail the whole batch', () async {
    final scanner = FakePdfScanner(
      PdfScanResult(
        candidates: [candidate(r'C:\src\ok.pdf'), candidate(r'C:\src\bad.pdf')],
      ),
    );
    final hasher = FakeFileHasher(failures: {r'C:\src\bad.pdf'});

    final report = await build(
      scanner: scanner,
      hasher: hasher,
    ).run(request, cancellation: MutableHashCancellation());

    expect(report.status, ImportBatchStatus.completed);
    expect(report.importedNewCount, 1);
    expect(report.failedCount, 1);
  });

  test(
    'Word .doc source import persists a source row without PDF inspection or conversion',
    () async {
      final scanner = FakePdfScanner(
        PdfScanResult(
          candidates: [
            candidate(r'C:\src\brief.doc', extension: '.doc', size: 321),
          ],
        ),
      );
      final inspector = FakePdfHealthInspector();

      final report = await build(
        scanner: scanner,
        hasher: FakeFileHasher(hashes: {r'C:\src\brief.doc': hex('e')}),
        inspector: inspector,
      ).run(request, cancellation: MutableHashCancellation());

      expect(report.status, ImportBatchStatus.completed);
      expect(report.files.single.status, ImportFileStatus.importedNew);
      expect(inspector.calls, 0, reason: 'Word sources are not PDF-inspected');

      final file = await (db.select(
        db.documentFiles,
      )..where((f) => f.absolutePath.equals(r'C:\src\brief.doc'))).getSingle();
      expect(file.extension, '.doc');
      expect(file.fileRoleKey, 'source_original');
      expect(file.mimeType, 'application/msword');
      expect(file.isReadOnlySource, isTrue);
      // No conversion is launched at import time: conversion happens inside
      // managed-copy when the user clicks "نسخ إلى المكتبة المدارة".
    },
  );

  test('cancellation produces a cancelled batch and partial report', () async {
    final cancel = MutableHashCancellation();
    final scanner = FakePdfScanner(
      PdfScanResult(
        candidates: [
          candidate(r'C:\src\a.pdf'),
          candidate(r'C:\src\b.pdf'),
          candidate(r'C:\src\c.pdf'),
        ],
      ),
    );
    // Cancel right after the first file hashes.
    final hasher = FakeFileHasher(
      cancelToken: cancel,
      cancelAfterPath: r'C:\src\a.pdf',
    );

    final report = await build(
      scanner: scanner,
      hasher: hasher,
    ).run(request, cancellation: cancel);

    expect(report.status, ImportBatchStatus.cancelled);
    expect(report.files.length, 1); // only a.pdf processed
    final batch = await (db.select(
      db.importBatches,
    )..where((b) => b.id.equals(report.batch!.id))).getSingle();
    expect(batch.statusKey, 'cancelled');
    expect(batch.completedAt, isNotNull);
  });

  test('retry processes only retryable failures', () async {
    final scanner = FakePdfScanner(
      PdfScanResult(
        candidates: [candidate(r'C:\src\a.pdf'), candidate(r'C:\src\d.pdf')],
      ),
    );
    final hasher = FakeFileHasher(
      hashes: {r'C:\src\a.pdf': hex('a')},
      failures: {r'C:\src\d.pdf'},
    );
    final coordinator = build(scanner: scanner, hasher: hasher);

    final first = await coordinator.run(
      request,
      cancellation: MutableHashCancellation(),
    );
    expect(first.failedCount, 1);
    expect(first.hasRetryableFailures, isTrue);

    // Now d.pdf hashes successfully on retry.
    final retryHasher = FakeFileHasher(hashes: {r'C:\src\d.pdf': hex('d')});
    final retryCoordinator = build(scanner: scanner, hasher: retryHasher);
    final retried = await retryCoordinator.retry(
      first,
      cancellation: MutableHashCancellation(),
    );

    expect(retried.status, ImportBatchStatus.completed);
    expect(retried.failedCount, 0);
    expect(retried.importedNewCount, 2);
    // Retry only re-hashed the failed file.
    expect(retryHasher.calls, 1);
    // Same batch reused.
    expect(retried.batch!.id, first.batch!.id);
    // a.pdf was not re-imported (still one row for it).
    final aRows = (await db.select(db.documentFiles).get())
        .where((f) => f.absolutePath == r'C:\src\a.pdf')
        .length;
    expect(aRows, 1);
  });

  test(
    'unsafe folder validation prevents batch creation and scanning',
    () async {
      final scanner = FakePdfScanner(const PdfScanResult(candidates: []));
      final hasher = FakeFileHasher();
      final coordinator = build(
        scanner: scanner,
        hasher: hasher,
        validator: FakeFolderValidator(
          const FolderValidationResult(
            code: FolderValidationCode.insideProtectedRoot,
          ),
        ),
      );

      final report = await coordinator.run(
        request,
        cancellation: MutableHashCancellation(),
      );

      expect(report.status, ImportBatchStatus.failed);
      expect(report.batch, isNull);
      expect(report.validation!.code, FolderValidationCode.insideProtectedRoot);
      expect(scanner.calls, 0); // never scanned
      expect(await db.select(db.importBatches).get(), isEmpty); // no batch
    },
  );

  test('scanner and health run through the injected isolate runner', () async {
    final spy = SpyRunner();
    final scanner = FakePdfScanner(
      PdfScanResult(
        candidates: [candidate(r'C:\src\a.pdf'), candidate(r'C:\src\b.pdf')],
      ),
    );
    final inspector = FakePdfHealthInspector();
    final coordinator = ImportCoordinator(
      validator: FakeFolderValidator(valid),
      scanner: scanner,
      hasher: FakeFileHasher(),
      inspector: inspector,
      repository: repo,
      clock: const SystemClock(),
      runner: spy.run,
    );

    await coordinator.run(request, cancellation: MutableHashCancellation());

    // One scan + one health inspect per candidate, all via the runner.
    expect(scanner.calls, 1);
    expect(inspector.calls, 2);
    expect(spy.calls, 3);
  });

  test('progress is monotonic and ends in finalizing', () async {
    final scanner = FakePdfScanner(
      PdfScanResult(
        candidates: [
          candidate(r'C:\src\a.pdf'),
          candidate(r'C:\src\b.pdf'),
          candidate(r'C:\src\c.pdf'),
        ],
      ),
    );
    final progresses = <ImportProgress>[];
    await build(scanner: scanner, hasher: FakeFileHasher()).run(
      request,
      cancellation: MutableHashCancellation(),
      onProgress: progresses.add,
    );

    expect(progresses.first.phase, ImportPhase.validating);
    expect(progresses.last.phase, ImportPhase.finalizing);
    // processed never decreases.
    for (int i = 1; i < progresses.length; i++) {
      expect(
        progresses[i].processed,
        greaterThanOrEqualTo(progresses[i - 1].processed),
      );
    }
    expect(progresses.last.processed, 3);
    expect(progresses.last.discovered, 3);
  });

  test('cancelled batch retains the full discovered count', () async {
    final cancel = MutableHashCancellation();
    final scanner = FakePdfScanner(
      PdfScanResult(
        candidates: [
          candidate(r'C:\src\a.pdf'),
          candidate(r'C:\src\b.pdf'),
          candidate(r'C:\src\c.pdf'),
        ],
      ),
    );
    final hasher = FakeFileHasher(
      cancelToken: cancel,
      cancelAfterPath: r'C:\src\a.pdf',
    );

    final report = await build(
      scanner: scanner,
      hasher: hasher,
    ).run(request, cancellation: cancel);

    expect(report.status, ImportBatchStatus.cancelled);
    // Processed report stays partial...
    expect(report.files.length, 1);
    // ...but the full scanned total is retained, not the partial length.
    expect(report.discoveredCount, 3);
    final batch = await (db.select(
      db.importBatches,
    )..where((b) => b.id.equals(report.batch!.id))).getSingle();
    expect(batch.statusKey, 'cancelled');
    expect(batch.discoveredCount, 3);
  });

  test('retry sets a fresh terminal completed_at on the same batch', () async {
    final scanner = FakePdfScanner(
      PdfScanResult(
        candidates: [candidate(r'C:\src\a.pdf'), candidate(r'C:\src\d.pdf')],
      ),
    );
    final hasher = FakeFileHasher(
      hashes: {r'C:\src\a.pdf': hex('a')},
      failures: {r'C:\src\d.pdf'},
    );
    final first = await build(
      scanner: scanner,
      hasher: hasher,
    ).run(request, cancellation: MutableHashCancellation());
    final int batchId = first.batch!.id;
    final firstRow = await (db.select(
      db.importBatches,
    )..where((b) => b.id.equals(batchId))).getSingle();
    expect(firstRow.statusKey, 'completed');
    expect(firstRow.completedAt, isNotNull);

    final retried = await build(
      scanner: scanner,
      hasher: FakeFileHasher(hashes: {r'C:\src\d.pdf': hex('d')}),
    ).retry(first, cancellation: MutableHashCancellation());

    final afterRow = await (db.select(
      db.importBatches,
    )..where((b) => b.id.equals(batchId))).getSingle();
    expect(retried.status, ImportBatchStatus.completed);
    expect(afterRow.statusKey, 'completed');
    expect(afterRow.completedAt, isNotNull);
  });

  test(
    'previously-imported path seen as unreadable on re-scan reports alreadyImported',
    () async {
      // Pre-import a.pdf so it has a completed (hashed) row.
      await repo.persistHashedFile(
        PreparedSourceFile(
          canonicalPath: r'C:\src\a.pdf',
          displayName: 'a.pdf',
          extension: '.pdf',
          sizeBytes: 100,
          sha256: hex('a'),
          health: PdfHealthStatus.healthy,
        ),
        operationId: 'seed',
        now: DateTime.utc(2026),
      );

      final report = await build(
        scanner: FakePdfScanner(
          PdfScanResult(candidates: [candidate(r'C:\src\a.pdf')]),
        ),
        hasher: FakeFileHasher(),
        inspector: FakePdfHealthInspector(
          byPath: {
            r'C:\src\a.pdf': const PdfHealthResult(
              status: PdfHealthStatus.unreadable,
              sizeBytes: 0,
            ),
          },
        ),
      ).run(request, cancellation: MutableHashCancellation());

      // Repository returns alreadyImported; coordinator must report that, not
      // unreadable.
      expect(report.status, ImportBatchStatus.completed);
      expect(report.files.single.status, ImportFileStatus.alreadyImported);
      expect(report.files.single.error, isNull);
      expect(report.alreadyImportedCount, 1);
      expect(report.failedCount, 0);
      // DB batch counters must match report counters.
      final batch = await (db.select(
        db.importBatches,
      )..where((b) => b.id.equals(report.batch!.id))).getSingle();
      expect(batch.importedCount, 0);
      expect(batch.failedCount, 0);
    },
  );

  test(
    'previously-imported path with hash failure on re-scan reports alreadyImported',
    () async {
      await repo.persistHashedFile(
        PreparedSourceFile(
          canonicalPath: r'C:\src\a.pdf',
          displayName: 'a.pdf',
          extension: '.pdf',
          sizeBytes: 100,
          sha256: hex('a'),
          health: PdfHealthStatus.healthy,
        ),
        operationId: 'seed',
        now: DateTime.utc(2026),
      );

      final report = await build(
        scanner: FakePdfScanner(
          PdfScanResult(candidates: [candidate(r'C:\src\a.pdf')]),
        ),
        hasher: FakeFileHasher(failures: {r'C:\src\a.pdf'}),
      ).run(request, cancellation: MutableHashCancellation());

      expect(report.status, ImportBatchStatus.completed);
      expect(report.files.single.status, ImportFileStatus.alreadyImported);
      expect(report.files.single.error, isNull);
      expect(report.alreadyImportedCount, 1);
      expect(report.failedCount, 0);
    },
  );

  group('persistence failure isolation (fake repository)', () {
    ImportCoordinator buildFake({
      required FakePdfScanner scanner,
      required FakeFileHasher hasher,
      required FakeImportRepository repository,
      FakePdfHealthInspector? inspector,
    }) {
      return ImportCoordinator(
        validator: FakeFolderValidator(valid),
        scanner: scanner,
        hasher: hasher,
        inspector: inspector ?? FakePdfHealthInspector(),
        repository: repository,
        clock: const SystemClock(),
        runner: syncRunner,
      );
    }

    test(
      'unreadable-entry persistence failure does not abort later files',
      () async {
        final report = await buildFake(
          scanner: FakePdfScanner(
            PdfScanResult(
              candidates: [
                candidate(r'C:\src\bad.pdf'),
                candidate(r'C:\src\ok.pdf'),
              ],
            ),
          ),
          hasher: FakeFileHasher(),
          inspector: FakePdfHealthInspector(
            byPath: {
              r'C:\src\bad.pdf': const PdfHealthResult(
                status: PdfHealthStatus.unreadable,
                sizeBytes: 0,
              ),
            },
          ),
          repository: FakeImportRepository(
            failPersistPaths: {r'C:\src\bad.pdf'},
          ),
        ).run(request, cancellation: MutableHashCancellation());

        expect(report.status, ImportBatchStatus.completed);
        expect(report.files.map((f) => f.status).toList(), [
          ImportFileStatus.persistenceFailed,
          ImportFileStatus.importedNew,
        ]);
      },
    );

    test(
      'hash-failed-entry persistence failure does not abort later files',
      () async {
        final report = await buildFake(
          scanner: FakePdfScanner(
            PdfScanResult(
              candidates: [
                candidate(r'C:\src\bad.pdf'),
                candidate(r'C:\src\ok.pdf'),
              ],
            ),
          ),
          hasher: FakeFileHasher(failures: {r'C:\src\bad.pdf'}),
          repository: FakeImportRepository(
            failPersistPaths: {r'C:\src\bad.pdf'},
          ),
        ).run(request, cancellation: MutableHashCancellation());

        expect(report.status, ImportBatchStatus.completed);
        expect(report.files.map((f) => f.status).toList(), [
          ImportFileStatus.persistenceFailed,
          ImportFileStatus.importedNew,
        ]);
      },
    );

    test(
      'scan-failed persistence failure (incl. secondary logging) does not abort later files',
      () async {
        final report = await buildFake(
          scanner: FakePdfScanner(
            PdfScanResult(
              candidates: [candidate(r'C:\src\ok.pdf')],
              failures: [
                const PdfScanFailure(
                  path: r'C:\src\locked',
                  message: 'could not enumerate',
                ),
              ],
            ),
          ),
          hasher: FakeFileHasher(),
          // Both the primary scan-failed event AND the secondary safe log throw.
          repository: FakeImportRepository(failRecordPaths: {r'C:\src\locked'}),
        ).run(request, cancellation: MutableHashCancellation());

        expect(report.status, ImportBatchStatus.completed);
        expect(report.files.map((f) => f.status).toList(), [
          ImportFileStatus.persistenceFailed,
          ImportFileStatus.importedNew,
        ]);
      },
    );

    test(
      'coordinator-level failure preserves already-produced reports',
      () async {
        final repository = FakeImportRepository(failOnComplete: true);
        final report = await buildFake(
          scanner: FakePdfScanner(
            PdfScanResult(candidates: [candidate(r'C:\src\ok.pdf')]),
          ),
          hasher: FakeFileHasher(),
          repository: repository,
        ).run(request, cancellation: MutableHashCancellation());

        // completeBatch threw, so the run failed safely â€” but the file processed
        // before finalization is preserved (not an empty report).
        expect(report.status, ImportBatchStatus.failed);
        expect(report.files.single.status, ImportFileStatus.importedNew);
        expect(report.discoveredCount, 1);
        expect(repository.lastStatus, ImportBatchStatus.failed);
      },
    );

    test(
      'inspector throws for first file, second file still imports',
      () async {
        final report = await buildFake(
          scanner: FakePdfScanner(
            PdfScanResult(
              candidates: [
                candidate(r'C:\src\bad.pdf'),
                candidate(r'C:\src\ok.pdf'),
              ],
            ),
          ),
          hasher: FakeFileHasher(),
          inspector: FakePdfHealthInspector(throwingPaths: {r'C:\src\bad.pdf'}),
          repository: FakeImportRepository(),
        ).run(request, cancellation: MutableHashCancellation());

        expect(report.status, ImportBatchStatus.completed);
        expect(report.files.map((f) => f.status).toList(), [
          ImportFileStatus
              .unreadable, // bad.pdf: _serviceException â†’ persisted
          ImportFileStatus.importedNew,
        ]);
        expect(report.failedCount, 1);
        expect(report.importedNewCount, 1);
      },
    );

    test(
      'hasher throws unexpectedly for first file, second file still imports',
      () async {
        final report = await buildFake(
          scanner: FakePdfScanner(
            PdfScanResult(
              candidates: [
                candidate(r'C:\src\bad.pdf'),
                candidate(r'C:\src\ok.pdf'),
              ],
            ),
          ),
          hasher: FakeFileHasher(throwingPaths: {r'C:\src\bad.pdf'}),
          repository: FakeImportRepository(),
        ).run(request, cancellation: MutableHashCancellation());

        expect(report.status, ImportBatchStatus.completed);
        expect(report.files.map((f) => f.status).toList(), [
          ImportFileStatus
              .hashFailed, // bad.pdf: _serviceException â†’ persisted
          ImportFileStatus.importedNew,
        ]);
        expect(report.failedCount, 1);
        expect(report.importedNewCount, 1);
      },
    );

    test(
      'completed batch retains partial-success counters after service exception',
      () async {
        final report = await buildFake(
          scanner: FakePdfScanner(
            PdfScanResult(
              candidates: [
                candidate(r'C:\src\bad.pdf'),
                candidate(r'C:\src\ok.pdf'),
                candidate(r'C:\src\ok2.pdf'),
              ],
            ),
          ),
          hasher: FakeFileHasher(throwingPaths: {r'C:\src\bad.pdf'}),
          repository: FakeImportRepository(),
        ).run(request, cancellation: MutableHashCancellation());

        expect(report.status, ImportBatchStatus.completed);
        expect(report.importedNewCount, 2);
        expect(report.failedCount, 1);
        expect(report.discoveredCount, 3);
      },
    );

    test(
      'failBatch throwing after coordinator failure still returns safe report',
      () async {
        // completeBatch throws AND failBatch also throws: both are swallowed.
        final repository = FakeImportRepository(
          failOnComplete: true,
          failFailBatch: true,
        );
        final report = await buildFake(
          scanner: FakePdfScanner(
            PdfScanResult(candidates: [candidate(r'C:\src\ok.pdf')]),
          ),
          hasher: FakeFileHasher(),
          repository: repository,
        ).run(request, cancellation: MutableHashCancellation());

        // Even with a double failure, the coordinator returns a safe report
        // with the files processed before finalization.
        expect(report.status, ImportBatchStatus.failed);
        expect(report.files.single.status, ImportFileStatus.importedNew);
        expect(report.discoveredCount, 1);
      },
    );

    test(
      'retry reopens the batch and clears the previous completed_at',
      () async {
        final repository = FakeImportRepository();
        final first = await buildFake(
          scanner: FakePdfScanner(
            PdfScanResult(candidates: [candidate(r'C:\src\d.pdf')]),
          ),
          hasher: FakeFileHasher(failures: {r'C:\src\d.pdf'}),
          repository: repository,
        ).run(request, cancellation: MutableHashCancellation());
        expect(first.hasRetryableFailures, isTrue);
        expect(repository.clearedCompletedAt, isFalse);

        final retried = await buildFake(
          scanner: FakePdfScanner(
            PdfScanResult(candidates: [candidate(r'C:\src\d.pdf')]),
          ),
          hasher: FakeFileHasher(hashes: {r'C:\src\d.pdf': hex('d')}),
          repository: repository,
        ).retry(first, cancellation: MutableHashCancellation());

        expect(retried.status, ImportBatchStatus.completed);
        expect(repository.clearedCompletedAt, isTrue);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Corrupted-file routing
  // ---------------------------------------------------------------------------

  group('corrupted-file routing', () {
    ImportCoordinator buildFake({
      required FakePdfScanner scanner,
      required FakeFileHasher hasher,
      FakePdfHealthInspector? inspector,
      required FakeImportRepository repository,
    }) {
      return ImportCoordinator(
        validator: FakeFolderValidator(valid),
        scanner: scanner,
        hasher: hasher,
        inspector: inspector ?? FakePdfHealthInspector(),
        repository: repository,
        clock: const SystemClock(),
        runner: syncRunner,
      );
    }

    const PdfHealthResult corruptedHealth = PdfHealthResult(
      status: PdfHealthStatus.corrupted,
      sizeBytes: 0,
    );

    test(
      'corrupted file gets ImportFileStatus.corrupted, not importedNew',
      () async {
        final fakeRepo = FakeImportRepository();
        final report = await buildFake(
          scanner: FakePdfScanner(
            PdfScanResult(candidates: [candidate(r'C:\src\bad.pdf')]),
          ),
          hasher: FakeFileHasher(),
          inspector: FakePdfHealthInspector(
            byPath: {r'C:\src\bad.pdf': corruptedHealth},
          ),
          repository: fakeRepo,
        ).run(request, cancellation: MutableHashCancellation());

        expect(report.status, ImportBatchStatus.completed);
        expect(report.files.single.status, ImportFileStatus.corrupted);
        expect(report.importedNewCount, 0);
        expect(report.duplicateCount, 0);
      },
    );

    test('corrupted file is never hashed', () async {
      final hasher = FakeFileHasher();
      await buildFake(
        scanner: FakePdfScanner(
          PdfScanResult(candidates: [candidate(r'C:\src\bad.pdf')]),
        ),
        hasher: hasher,
        inspector: FakePdfHealthInspector(
          byPath: {r'C:\src\bad.pdf': corruptedHealth},
        ),
        repository: FakeImportRepository(),
      ).run(request, cancellation: MutableHashCancellation());

      expect(hasher.calls, 0); // hashing must never be invoked for corrupted
    });

    test(
      'corrupted file preserves PdfHealthStatus.corrupted (not coerced to unreadable)',
      () async {
        final fakeRepo = FakeImportRepository();
        await buildFake(
          scanner: FakePdfScanner(
            PdfScanResult(candidates: [candidate(r'C:\src\bad.pdf')]),
          ),
          hasher: FakeFileHasher(),
          inspector: FakePdfHealthInspector(
            byPath: {r'C:\src\bad.pdf': corruptedHealth},
          ),
          repository: fakeRepo,
        ).run(request, cancellation: MutableHashCancellation());

        expect(fakeRepo.lastFailedFile?.health, PdfHealthStatus.corrupted);
        expect(fakeRepo.lastFailedFile?.errorCode, 'corrupted');
      },
    );

    test('corrupted file carries ImportErrorCode.corrupted', () async {
      final report = await buildFake(
        scanner: FakePdfScanner(
          PdfScanResult(candidates: [candidate(r'C:\src\bad.pdf')]),
        ),
        hasher: FakeFileHasher(),
        inspector: FakePdfHealthInspector(
          byPath: {r'C:\src\bad.pdf': corruptedHealth},
        ),
        repository: FakeImportRepository(),
      ).run(request, cancellation: MutableHashCancellation());

      expect(report.files.single.error?.code, ImportErrorCode.corrupted);
    });

    test('corrupted file counts in failedCount and is retryable', () async {
      final report = await buildFake(
        scanner: FakePdfScanner(
          PdfScanResult(candidates: [candidate(r'C:\src\bad.pdf')]),
        ),
        hasher: FakeFileHasher(),
        inspector: FakePdfHealthInspector(
          byPath: {r'C:\src\bad.pdf': corruptedHealth},
        ),
        repository: FakeImportRepository(),
      ).run(request, cancellation: MutableHashCancellation());

      expect(report.failedCount, 1);
      expect(report.hasRetryableFailures, isTrue);
      expect(report.retryableFiles.single.status, ImportFileStatus.corrupted);
    });

    test('corrupted file does not abort later files', () async {
      final report = await buildFake(
        scanner: FakePdfScanner(
          PdfScanResult(
            candidates: [
              candidate(r'C:\src\bad.pdf'),
              candidate(r'C:\src\ok.pdf'),
            ],
          ),
        ),
        hasher: FakeFileHasher(),
        inspector: FakePdfHealthInspector(
          byPath: {r'C:\src\bad.pdf': corruptedHealth},
        ),
        repository: FakeImportRepository(),
      ).run(request, cancellation: MutableHashCancellation());

      expect(report.status, ImportBatchStatus.completed);
      expect(report.files.map((f) => f.status).toList(), [
        ImportFileStatus.corrupted,
        ImportFileStatus.importedNew,
      ]);
      expect(report.failedCount, 1);
      expect(report.importedNewCount, 1);
    });

    test(
      'corrupted file persistence failure does not abort later files',
      () async {
        final report = await buildFake(
          scanner: FakePdfScanner(
            PdfScanResult(
              candidates: [
                candidate(r'C:\src\bad.pdf'),
                candidate(r'C:\src\ok.pdf'),
              ],
            ),
          ),
          hasher: FakeFileHasher(),
          inspector: FakePdfHealthInspector(
            byPath: {r'C:\src\bad.pdf': corruptedHealth},
          ),
          repository: FakeImportRepository(
            failPersistPaths: {r'C:\src\bad.pdf'},
          ),
        ).run(request, cancellation: MutableHashCancellation());

        expect(report.status, ImportBatchStatus.completed);
        expect(report.files.map((f) => f.status).toList(), [
          ImportFileStatus.persistenceFailed,
          ImportFileStatus.importedNew,
        ]);
      },
    );

    test(
      'previously-imported same-path on corrupted rescan stays alreadyImported',
      () async {
        // Pre-import via real DB so the path has a known sha256 hash.
        await repo.persistHashedFile(
          PreparedSourceFile(
            canonicalPath: r'C:\src\a.pdf',
            displayName: 'a.pdf',
            extension: '.pdf',
            sizeBytes: 100,
            sha256: hex('a'),
            health: PdfHealthStatus.healthy,
          ),
          operationId: 'seed',
          now: DateTime.utc(2026),
        );

        final report = await build(
          scanner: FakePdfScanner(
            PdfScanResult(candidates: [candidate(r'C:\src\a.pdf')]),
          ),
          hasher: FakeFileHasher(),
          inspector: FakePdfHealthInspector(
            byPath: {r'C:\src\a.pdf': corruptedHealth},
          ),
        ).run(request, cancellation: MutableHashCancellation());

        // The path was previously successfully imported; the repository returns
        // alreadyImported and the coordinator must not downgrade it to corrupted.
        expect(report.files.single.status, ImportFileStatus.alreadyImported);
        expect(report.files.single.error, isNull);
        expect(report.failedCount, 0);
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Paired-source detection
  // ---------------------------------------------------------------------------

  group('paired-source detection', () {
    test(
      'same-folder same-basename .doc+.pdf: PDF imported normally, .doc paired',
      () async {
        final report = await build(
          scanner: FakePdfScanner(
            PdfScanResult(
              candidates: [
                candidate(r'C:\src\brief.doc', extension: '.doc'),
                candidate(r'C:\src\brief.pdf'),
              ],
            ),
          ),
          hasher: FakeFileHasher(
            hashes: {
              r'C:\src\brief.doc': hex('d'),
              r'C:\src\brief.pdf': hex('f'),
            },
          ),
        ).run(request, cancellation: MutableHashCancellation());

        expect(report.status, ImportBatchStatus.completed);

        final pdfReport = report.files.firstWhere(
          (f) => f.path.endsWith('.pdf'),
        );
        final docReport = report.files.firstWhere(
          (f) => f.path.endsWith('.doc'),
        );

        expect(pdfReport.status, ImportFileStatus.importedNew);
        expect(docReport.status, ImportFileStatus.pairedWordSource);
      },
    );

    test('paired .doc and .pdf share the same document ID', () async {
      final report = await build(
        scanner: FakePdfScanner(
          PdfScanResult(
            candidates: [
              candidate(r'C:\src\brief.doc', extension: '.doc'),
              candidate(r'C:\src\brief.pdf'),
            ],
          ),
        ),
        hasher: FakeFileHasher(
          hashes: {
            r'C:\src\brief.doc': hex('d'),
            r'C:\src\brief.pdf': hex('f'),
          },
        ),
      ).run(request, cancellation: MutableHashCancellation());

      final pdfReport = report.files.firstWhere((f) => f.path.endsWith('.pdf'));
      final docReport = report.files.firstWhere((f) => f.path.endsWith('.doc'));

      expect(docReport.documentId, isNotNull);
      expect(docReport.documentId, pdfReport.documentId);

      // DB: only one document row created for the pair.
      final docs = await db.select(db.documents).get();
      expect(docs.length, 1);
    });

    test('pairedWordSourceCount equals 1, counts in importedCount', () async {
      final report = await build(
        scanner: FakePdfScanner(
          PdfScanResult(
            candidates: [
              candidate(r'C:\src\brief.doc', extension: '.doc'),
              candidate(r'C:\src\brief.pdf'),
            ],
          ),
        ),
        hasher: FakeFileHasher(
          hashes: {
            r'C:\src\brief.doc': hex('d'),
            r'C:\src\brief.pdf': hex('f'),
          },
        ),
      ).run(request, cancellation: MutableHashCancellation());

      expect(report.pairedWordSourceCount, 1);
      expect(report.importedNewCount, 1);
      expect(report.importedCount, 2); // PDF (new) + .doc (paired)
    });

    test(
      'paired_source_detected audit event is recorded for the .doc',
      () async {
        await build(
          scanner: FakePdfScanner(
            PdfScanResult(
              candidates: [
                candidate(r'C:\src\brief.doc', extension: '.doc'),
                candidate(r'C:\src\brief.pdf'),
              ],
            ),
          ),
          hasher: FakeFileHasher(
            hashes: {
              r'C:\src\brief.doc': hex('d'),
              r'C:\src\brief.pdf': hex('f'),
            },
          ),
        ).run(request, cancellation: MutableHashCancellation());

        final events = await db.select(db.fileEvents).get();
        expect(
          events.any((e) => e.eventTypeKey == 'paired_source_detected'),
          isTrue,
        );
      },
    );

    test('different basenames in the same folder are not paired', () async {
      final report = await build(
        scanner: FakePdfScanner(
          PdfScanResult(
            candidates: [
              candidate(r'C:\src\brief.doc', extension: '.doc'),
              candidate(r'C:\src\contract.pdf'),
            ],
          ),
        ),
        hasher: FakeFileHasher(
          hashes: {
            r'C:\src\brief.doc': hex('d'),
            r'C:\src\contract.pdf': hex('f'),
          },
        ),
      ).run(request, cancellation: MutableHashCancellation());

      // Unpaired .doc is imported as source_original; conversion happens later in managed-copy.
      final docReport = report.files.firstWhere((f) => f.path.endsWith('.doc'));
      expect(docReport.status, ImportFileStatus.importedNew);

      // Both files have distinct documents.
      final docs = await db.select(db.documents).get();
      expect(docs.length, 2);
    });

    test(
      '.doc in a different subfolder is not paired with .pdf in parent',
      () async {
        final report = await build(
          scanner: FakePdfScanner(
            PdfScanResult(
              candidates: [
                candidate(r'C:\src\sub\brief.doc', extension: '.doc'),
                candidate(r'C:\src\brief.pdf'),
              ],
            ),
          ),
          hasher: FakeFileHasher(
            hashes: {
              r'C:\src\sub\brief.doc': hex('d'),
              r'C:\src\brief.pdf': hex('f'),
            },
          ),
        ).run(request, cancellation: MutableHashCancellation());

        final docReport = report.files.firstWhere(
          (f) => f.path.endsWith('.doc'),
        );
        expect(docReport.status, ImportFileStatus.importedNew);
      },
    );

    test('.doc without paired PDF is imported as source_original', () async {
      final report = await build(
        scanner: FakePdfScanner(
          PdfScanResult(
            candidates: [candidate(r'C:\src\brief.doc', extension: '.doc')],
          ),
        ),
        hasher: FakeFileHasher(hashes: {r'C:\src\brief.doc': hex('d')}),
      ).run(request, cancellation: MutableHashCancellation());

      expect(report.files.single.status, ImportFileStatus.importedNew);
      // Conversion is deferred to managed-copy, not triggered at import time.
    });

    test('pairing is case-insensitive on basename and extension', () async {
      final report = await build(
        scanner: FakePdfScanner(
          PdfScanResult(
            candidates: [
              // Mixed-case name and extension
              candidate(
                r'C:\src\Brief.DOC',
                name: 'Brief.DOC',
                extension: '.DOC',
              ),
              candidate(r'C:\src\brief.pdf'),
            ],
          ),
        ),
        hasher: FakeFileHasher(
          hashes: {
            r'C:\src\Brief.DOC': hex('d'),
            r'C:\src\brief.pdf': hex('f'),
          },
        ),
      ).run(request, cancellation: MutableHashCancellation());

      final docReport = report.files.firstWhere((f) => f.path.endsWith('.DOC'));
      expect(docReport.status, ImportFileStatus.pairedWordSource);
    });

    test(
      'if PDF import fails, paired .doc falls back to standalone import',
      () async {
        // PDF health inspector marks the PDF as unreadable (import fails).
        final report = await build(
          scanner: FakePdfScanner(
            PdfScanResult(
              candidates: [
                candidate(r'C:\src\brief.doc', extension: '.doc'),
                candidate(r'C:\src\brief.pdf'),
              ],
            ),
          ),
          hasher: FakeFileHasher(hashes: {r'C:\src\brief.doc': hex('d')}),
          inspector: FakePdfHealthInspector(
            byPath: {
              r'C:\src\brief.pdf': const PdfHealthResult(
                status: PdfHealthStatus.unreadable,
                sizeBytes: 0,
              ),
            },
          ),
        ).run(request, cancellation: MutableHashCancellation());

        final pdfReport = report.files.firstWhere(
          (f) => f.path.endsWith('.pdf'),
        );
        final docReport = report.files.firstWhere(
          (f) => f.path.endsWith('.doc'),
        );

        expect(pdfReport.status, ImportFileStatus.unreadable);
        // .doc falls back to standalone source_original import; conversion deferred to managed-copy.
        expect(docReport.status, ImportFileStatus.importedNew);
      },
    );

    test(
      '.doc-before-.pdf scan order still works: ordering ensures PDF is processed first',
      () async {
        // Scanner returns .doc before .pdf — coordinator must reorder.
        final report = await build(
          scanner: FakePdfScanner(
            PdfScanResult(
              candidates: [
                candidate(r'C:\src\brief.doc', extension: '.doc'),
                candidate(r'C:\src\brief.pdf'),
              ],
            ),
          ),
          hasher: FakeFileHasher(
            hashes: {
              r'C:\src\brief.doc': hex('d'),
              r'C:\src\brief.pdf': hex('f'),
            },
          ),
        ).run(request, cancellation: MutableHashCancellation());

        final docReport = report.files.firstWhere(
          (f) => f.path.endsWith('.doc'),
        );
        expect(docReport.status, ImportFileStatus.pairedWordSource);
      },
    );
  });
}
