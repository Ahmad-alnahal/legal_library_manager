// test/features/related_files/drift_related_file_candidate_repository_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/constants/domain_keys.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/database/seeding/reference_seeder.dart';
import 'package:legal_library_manager/features/related_files/data/repositories/drift_related_file_candidate_repository.dart';
import 'package:legal_library_manager/features/related_files/domain/entities/candidate_input.dart';
import 'package:legal_library_manager/features/related_files/domain/entities/candidate_reason.dart';
import 'package:legal_library_manager/features/related_files/domain/entities/candidate_status.dart';
import 'package:sqlite3/common.dart';

void main() {
  late AppDatabase db;
  late DriftRelatedFileCandidateRepository repo;

  final DateTime now = DateTime.utc(2026, 6, 28, 10);
  final String nowIso = now.toIso8601String();

  setUp(() async {
    db = AppDatabase.inMemory();
    await ReferenceSeeder(db).seedAll();
    repo = DriftRelatedFileCandidateRepository(db);
  });

  tearDown(() => db.close());

  Future<int> insertDoc() => db
      .into(db.documents)
      .insert(DocumentsCompanion.insert(createdAt: nowIso, updatedAt: nowIso));

  Future<int> insertFile(int docId, String path, String ext) => db
      .into(db.documentFiles)
      .insert(
        DocumentFilesCompanion.insert(
          documentId: docId,
          fileRoleKey: FileRoleKey.sourceOriginal,
          fileName: path.split(r'\').last,
          absolutePath: path,
          extension: ext,
          fileSizeBytes: 1000,
          createdAt: nowIso,
          updatedAt: nowIso,
        ),
      );

  CandidateInput makeInput(int a, int b) => CandidateInput(
    fileAId: a,
    fileBId: b,
    reason: CandidateReason.similarBasename,
    confidence: 0.75,
  );

  // ── Test 1: single pair stored correctly ─────────────────────────────────────
  test('upsertCandidates stores single pair with pending status', () async {
    final docId = await insertDoc();
    final fileA = await insertFile(docId, r'C:\a.pdf', '.pdf');
    final fileB = await insertFile(docId, r'C:\b.pdf', '.pdf');

    final inserted = await repo.upsertCandidates([
      makeInput(fileA, fileB),
    ], now);

    expect(inserted, 1);
    final rows = await db.select(db.relatedFileCandidates).get();
    expect(rows, hasLength(1));
    expect(rows.first.fileAId, fileA);
    expect(rows.first.fileBId, fileB);
    expect(rows.first.statusKey, 'pending');
    expect(rows.first.reasonKey, CandidateReason.similarBasename.key);
    expect(rows.first.confidence, closeTo(0.75, 0.001));
  });

  // ── Test 2: upsert idempotency ────────────────────────────────────────────────
  test('upsertCandidates is idempotent — second call inserts 0 rows', () async {
    final docId = await insertDoc();
    final fileA = await insertFile(docId, r'C:\a.pdf', '.pdf');
    final fileB = await insertFile(docId, r'C:\b.pdf', '.pdf');

    await repo.upsertCandidates([makeInput(fileA, fileB)], now);
    final second = await repo.upsertCandidates([makeInput(fileA, fileB)], now);

    expect(second, 0);
    expect(await db.select(db.relatedFileCandidates).get(), hasLength(1));
  });

  // ── Test 3: confirmed pair not overwritten ────────────────────────────────────
  test(
    'upsertCandidates does not overwrite an existing confirmed pair',
    () async {
      final docId = await insertDoc();
      final fileA = await insertFile(docId, r'C:\a.pdf', '.pdf');
      final fileB = await insertFile(docId, r'C:\b.pdf', '.pdf');

      await repo.upsertCandidates([makeInput(fileA, fileB)], now);
      final row = (await db.select(db.relatedFileCandidates).get()).first;
      await repo.updateStatus(
        row.id,
        CandidateStatus.confirmed,
        now.add(const Duration(hours: 1)),
      );

      await repo.upsertCandidates([makeInput(fileA, fileB)], now);

      final rows = await db.select(db.relatedFileCandidates).get();
      expect(rows, hasLength(1));
      expect(rows.first.statusKey, CandidateStatus.confirmed.key);
    },
  );

  // ── Test 4: DB CHECK rejects equal IDs ───────────────────────────────────────
  test('DB rejects row where file_a_id = file_b_id', () async {
    final docId = await insertDoc();
    final fileA = await insertFile(docId, r'C:\a.pdf', '.pdf');

    await expectLater(
      db
          .into(db.relatedFileCandidates)
          .insert(
            RelatedFileCandidatesCompanion.insert(
              fileAId: fileA,
              fileBId: fileA,
              reasonKey: CandidateReason.similarBasename.key,
              confidence: 0.5,
              createdAt: nowIso,
              updatedAt: nowIso,
            ),
          ),
      throwsA(isA<SqliteException>()),
    );
  });

  // ── Test 5: DB CHECK rejects reversed IDs ────────────────────────────────────
  test('DB rejects row where file_a_id > file_b_id', () async {
    final docId = await insertDoc();
    final fileA = await insertFile(docId, r'C:\a.pdf', '.pdf');
    final fileB = await insertFile(docId, r'C:\b.pdf', '.pdf');

    await expectLater(
      db
          .into(db.relatedFileCandidates)
          .insert(
            RelatedFileCandidatesCompanion.insert(
              fileAId: fileB,
              fileBId: fileA,
              reasonKey: CandidateReason.similarBasename.key,
              confidence: 0.5,
              createdAt: nowIso,
              updatedAt: nowIso,
            ),
          ),
      throwsA(isA<SqliteException>()),
    );
  });

  // ── Test 6: listByStatus ───────────────────────────────────────────────────────
  test(
    'listByStatus returns only rows matching the requested status',
    () async {
      final docId = await insertDoc();
      final fileA = await insertFile(docId, r'C:\a.pdf', '.pdf');
      final fileB = await insertFile(docId, r'C:\b.pdf', '.pdf');
      final fileC = await insertFile(docId, r'C:\c.pdf', '.pdf');

      await repo.upsertCandidates([makeInput(fileA, fileB)], now);
      await repo.upsertCandidates([makeInput(fileA, fileC)], now);

      final pending = await repo.listByStatus(CandidateStatus.pending);
      expect(pending, hasLength(2));

      await repo.updateStatus(pending.first.id, CandidateStatus.confirmed, now);
      final stillPending = await repo.listByStatus(CandidateStatus.pending);
      expect(stillPending, hasLength(1));
      final confirmed = await repo.listByStatus(CandidateStatus.confirmed);
      expect(confirmed, hasLength(1));
    },
  );

  // ── Test 7: listForFile ────────────────────────────────────────────────────────
  test(
    'listForFile returns candidates where fileId is on either side',
    () async {
      final docId = await insertDoc();
      final fileA = await insertFile(docId, r'C:\a.pdf', '.pdf');
      final fileB = await insertFile(docId, r'C:\b.pdf', '.pdf');
      final fileC = await insertFile(docId, r'C:\c.pdf', '.pdf');

      await repo.upsertCandidates([
        makeInput(fileA, fileB),
        makeInput(fileB, fileC),
      ], now);

      final forB = await repo.listForFile(fileB);
      expect(forB, hasLength(2));

      final forA = await repo.listForFile(fileA);
      expect(forA, hasLength(1));
      expect(forA.first.fileAId, fileA);
    },
  );

  // ── Test 8: updateStatus ───────────────────────────────────────────────────────
  test(
    'updateStatus changes status and updatedAt, leaves other fields unchanged',
    () async {
      final docId = await insertDoc();
      final fileA = await insertFile(docId, r'C:\a.pdf', '.pdf');
      final fileB = await insertFile(docId, r'C:\b.pdf', '.pdf');

      await repo.upsertCandidates([makeInput(fileA, fileB)], now);
      final before = (await repo.listByStatus(CandidateStatus.pending)).first;

      final later = now.add(const Duration(hours: 2));
      await repo.updateStatus(before.id, CandidateStatus.rejected, later);

      final after = (await repo.listByStatus(CandidateStatus.rejected)).first;
      expect(after.status, CandidateStatus.rejected);
      expect(after.updatedAt, later);
      expect(after.createdAt, before.createdAt);
      expect(after.fileAId, before.fileAId);
      expect(after.confidence, before.confidence);
    },
  );

  // ── Test 9: multiple candidates returned by listByStatus ────────────────────
  test('listByStatus returns all matching candidates', () async {
    final docId = await insertDoc();
    final fileA = await insertFile(docId, r'C:\a.pdf', '.pdf');
    final fileB = await insertFile(docId, r'C:\b.pdf', '.pdf');
    final fileC = await insertFile(docId, r'C:\c.pdf', '.pdf');

    await repo.upsertCandidates([
      makeInput(fileA, fileB),
      makeInput(fileA, fileC),
      makeInput(fileB, fileC),
    ], now);

    final all = await repo.listByStatus(CandidateStatus.pending);
    expect(all, hasLength(3));
  });
}
