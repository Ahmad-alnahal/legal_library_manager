// test/features/related_files/drift_related_file_review_test.dart

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/database/app_database.dart';
import 'package:legal_library_manager/core/database/seeding/reference_seeder.dart';
import 'package:legal_library_manager/features/related_files/data/repositories/drift_related_file_candidate_repository.dart';
import 'package:legal_library_manager/features/related_files/domain/entities/candidate_input.dart';
import 'package:legal_library_manager/features/related_files/domain/entities/candidate_reason.dart';
import 'package:legal_library_manager/features/related_files/domain/entities/candidate_status.dart';

void main() {
  late AppDatabase db;
  late DriftRelatedFileCandidateRepository repo;

  final DateTime now = DateTime.utc(2026, 6, 28, 12);
  final String nowIso = now.toIso8601String();

  setUp(() async {
    db = AppDatabase.inMemory();
    await ReferenceSeeder(db).seedAll();
    repo = DriftRelatedFileCandidateRepository(db);
  });

  tearDown(() => db.close());

  // ── Helpers ───────────────────────────────────────────────────────────────

  Future<int> insertDoc({String? title, String? code}) => db
      .into(db.documents)
      .insert(
        DocumentsCompanion(
          createdAt: Value(nowIso),
          updatedAt: Value(nowIso),
          title: Value(title),
          documentCode: Value(code),
        ),
      );

  Future<int> insertFile(int docId, String path, String ext) => db
      .into(db.documentFiles)
      .insert(
        DocumentFilesCompanion.insert(
          documentId: docId,
          fileRoleKey: 'source_original',
          fileName: path.split(r'\').last,
          absolutePath: path,
          extension: ext,
          fileSizeBytes: 1000,
          createdAt: nowIso,
          updatedAt: nowIso,
        ),
      );

  Future<void> insertCandidate(
    int fileA,
    int fileB, {
    double confidence = 0.75,
    CandidateReason reason = CandidateReason.similarBasename,
  }) => repo.upsertCandidates([
    CandidateInput(
      fileAId: fileA,
      fileBId: fileB,
      reason: reason,
      confidence: confidence,
    ),
  ], now);

  // ── Tests ─────────────────────────────────────────────────────────────────

  // Test 1
  test('listPendingForReview returns empty list when no candidates', () async {
    final rows = await repo.listPendingForReview();
    expect(rows, isEmpty);
  });

  // Test 2
  test('listPendingForReview returns one row with correct fields', () async {
    final docA = await insertDoc(title: 'قانون العمل', code: 'DOC-0000001');
    final docB = await insertDoc();
    final fileA = await insertFile(docA, r'C:\legal\contract.pdf', '.pdf');
    final fileB = await insertFile(docB, r'C:\legal\contract.doc', '.doc');
    await insertCandidate(
      fileA,
      fileB,
      confidence: 0.90,
      reason: CandidateReason.docPdfPair,
    );

    final rows = await repo.listPendingForReview();

    expect(rows, hasLength(1));
    final r = rows.first;
    expect(r.candidateId, isPositive);
    expect(r.confidence, closeTo(0.90, 0.001));
    expect(r.reason, CandidateReason.docPdfPair);
    expect(r.fileAId, fileA);
    expect(r.fileAName, 'contract.pdf');
    expect(r.fileAPath, r'C:\legal\contract.pdf');
    expect(r.fileAExtension, '.pdf');
    expect(r.documentAId, docA);
    expect(r.documentATitle, 'قانون العمل');
    expect(r.documentACode, 'DOC-0000001');
    expect(r.fileBId, fileB);
    expect(r.fileBName, 'contract.doc');
    expect(r.fileBExtension, '.doc');
    expect(r.documentBId, docB);
    expect(r.documentBTitle, isNull);
    expect(r.documentBCode, isNull);
  });

  // Test 3
  test('listPendingForReview orders by confidence DESC', () async {
    final docA = await insertDoc();
    final docB = await insertDoc();
    final docC = await insertDoc();
    final fileA = await insertFile(docA, r'C:\a.pdf', '.pdf');
    final fileB = await insertFile(docB, r'C:\b.pdf', '.pdf');
    final fileC = await insertFile(docC, r'C:\c.pdf', '.pdf');
    await insertCandidate(fileA, fileB, confidence: 0.50);
    await insertCandidate(fileA, fileC, confidence: 0.90);

    final rows = await repo.listPendingForReview();

    expect(rows, hasLength(2));
    expect(rows[0].confidence, closeTo(0.90, 0.001));
    expect(rows[1].confidence, closeTo(0.50, 0.001));
  });

  // Test 4
  test('listPendingForReview excludes non-pending candidates', () async {
    final docA = await insertDoc();
    final docB = await insertDoc();
    final fileA = await insertFile(docA, r'C:\a.pdf', '.pdf');
    final fileB = await insertFile(docB, r'C:\b.pdf', '.pdf');
    await insertCandidate(fileA, fileB, confidence: 0.70);

    // Confirm that pending is returned before the status change
    final rows1 = await repo.listPendingForReview();
    expect(rows1, hasLength(1));

    // Mark as confirmed — should disappear from the review queue
    await repo.updateStatus(
      rows1.first.candidateId,
      CandidateStatus.confirmed,
      now,
    );

    final rows2 = await repo.listPendingForReview();
    expect(rows2, isEmpty);
  });

  // Test 5
  test('listPendingForReview respects the limit parameter', () async {
    // Insert 5 candidates across 6 different documents/files, request limit=3
    final docs = await Future.wait(List.generate(6, (_) => insertDoc()));
    final files = await Future.wait(
      List.generate(6, (i) => insertFile(docs[i], 'C:\\f$i.pdf', '.pdf')),
    );
    // Create 5 pairs: files[0]–files[5], files[1]–files[5], …, files[4]–files[5]
    // Each must satisfy file_a_id < file_b_id
    for (int i = 0; i < 5; i++) {
      final a = files[i] < files[5] ? files[i] : files[5];
      final b = files[i] < files[5] ? files[5] : files[i];
      await insertCandidate(a, b, confidence: (5 - i) * 0.1);
    }

    final rows = await repo.listPendingForReview(limit: 3);
    expect(rows, hasLength(3));
  });

  // Test 6
  test(
    'listPendingForReview returns nullable document fields correctly',
    () async {
      final docA = await insertDoc(); // title and code are null
      final docB = await insertDoc();
      final fileA = await insertFile(docA, r'C:\a.pdf', '.pdf');
      final fileB = await insertFile(docB, r'C:\b.pdf', '.pdf');
      await insertCandidate(fileA, fileB);

      final rows = await repo.listPendingForReview();
      expect(rows.first.documentATitle, isNull);
      expect(rows.first.documentACode, isNull);
      // workflow_status_key has a default value of 'imported'
      expect(rows.first.documentAWorkflowStatus, isNotNull);
    },
  );
}
