// test/features/related_files/candidate_use_cases_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/constants/domain_keys.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/database/seeding/reference_seeder.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/features/related_files/application/load_pending_candidates_use_case.dart';
import 'package:legal_library_manager/features/related_files/application/update_candidate_status_use_case.dart';
import 'package:legal_library_manager/features/related_files/data/repositories/drift_related_file_candidate_repository.dart';
import 'package:legal_library_manager/features/related_files/domain/entities/candidate_input.dart';
import 'package:legal_library_manager/features/related_files/domain/entities/candidate_reason.dart';
import 'package:legal_library_manager/features/related_files/domain/entities/candidate_status.dart';

class _FixedClock extends Clock {
  const _FixedClock(this._now);
  final DateTime _now;
  @override
  DateTime nowUtc() => _now;
}

void main() {
  late AppDatabase db;
  late DriftRelatedFileCandidateRepository repo;
  late LoadPendingCandidatesUseCase loadPending;
  late UpdateCandidateStatusUseCase updateStatus;

  final DateTime now = DateTime.utc(2026, 6, 28, 10);
  final String nowIso = now.toIso8601String();

  setUp(() async {
    db = AppDatabase.inMemory();
    await ReferenceSeeder(db).seedAll();
    repo = DriftRelatedFileCandidateRepository(db);
    loadPending = LoadPendingCandidatesUseCase(repo);
    updateStatus = UpdateCandidateStatusUseCase(repo, _FixedClock(now));
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

  CandidateInput makeInput(int a, int b, {double confidence = 0.75}) =>
      CandidateInput(
        fileAId: a,
        fileBId: b,
        reason: CandidateReason.similarBasename,
        confidence: confidence,
      );

  group('LoadPendingCandidatesUseCase', () {
    test('returns empty list when no candidates exist', () async {
      final result = await loadPending();
      expect(result, isEmpty);
    });

    test(
      'returns pending candidates sorted confidence-first',
      () async {
        final docId = await insertDoc();
        final fileA = await insertFile(docId, r'C:\a.pdf', '.pdf');
        final fileB = await insertFile(docId, r'C:\b.pdf', '.pdf');
        final fileC = await insertFile(docId, r'C:\c.pdf', '.pdf');

        await repo.upsertCandidates([
          makeInput(fileA, fileB, confidence: 0.5),
        ], now);
        await repo.upsertCandidates([
          makeInput(fileB, fileC, confidence: 0.9),
        ], now);

        final result = await loadPending();

        expect(result, hasLength(2));
        expect(result.first.confidence, closeTo(0.9, 0.001));
        expect(result.last.confidence, closeTo(0.5, 0.001));
      },
    );

    test('excludes non-pending candidates', () async {
      final docId = await insertDoc();
      final fileA = await insertFile(docId, r'C:\a.pdf', '.pdf');
      final fileB = await insertFile(docId, r'C:\b.pdf', '.pdf');
      final fileC = await insertFile(docId, r'C:\c.pdf', '.pdf');

      await repo.upsertCandidates([makeInput(fileA, fileB)], now);
      await repo.upsertCandidates([makeInput(fileB, fileC)], now);

      final pending = await repo.listByStatus(CandidateStatus.pending);
      await repo.updateStatus(pending.first.id, CandidateStatus.confirmed, now);

      final result = await loadPending();
      expect(result, hasLength(1));
    });

    test('respects the limit parameter', () async {
      final docId = await insertDoc();
      final files = <int>[];
      for (var i = 0; i < 6; i++) {
        files.add(await insertFile(docId, 'C:\\f$i.pdf', '.pdf'));
      }
      for (var i = 0; i < 5; i++) {
        await repo.upsertCandidates([
          makeInput(files[i], files[i + 1]),
        ], now);
      }

      final result = await loadPending(limit: 2);
      expect(result, hasLength(2));
    });
  });

  group('UpdateCandidateStatusUseCase', () {
    Future<int> insertPendingCandidate() async {
      final docId = await insertDoc();
      final fileA = await insertFile(docId, r'C:\a.pdf', '.pdf');
      final fileB = await insertFile(docId, r'C:\b.pdf', '.pdf');
      await repo.upsertCandidates([makeInput(fileA, fileB)], now);
      final row = (await db.select(db.relatedFileCandidates).get()).first;
      return row.id;
    }

    test('marks a pending candidate as confirmed', () async {
      final id = await insertPendingCandidate();

      await updateStatus(id, CandidateStatus.confirmed);

      final pending = await repo.listPendingForReview();
      expect(pending.any((r) => r.candidateId == id), isFalse);

      final row = await (db.select(
        db.relatedFileCandidates,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(row.statusKey, CandidateStatus.confirmed.key);
    });

    test('marks a pending candidate as rejected', () async {
      final id = await insertPendingCandidate();

      await updateStatus(id, CandidateStatus.rejected);

      final pending = await repo.listPendingForReview();
      expect(pending.any((r) => r.candidateId == id), isFalse);

      final row = await (db.select(
        db.relatedFileCandidates,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(row.statusKey, CandidateStatus.rejected.key);
    });

    test('marks a pending candidate as dismissed', () async {
      final id = await insertPendingCandidate();

      await updateStatus(id, CandidateStatus.dismissed);

      final pending = await repo.listPendingForReview();
      expect(pending.any((r) => r.candidateId == id), isFalse);

      final row = await (db.select(
        db.relatedFileCandidates,
      )..where((t) => t.id.equals(id))).getSingle();
      expect(row.statusKey, CandidateStatus.dismissed.key);
    });
  });
}
