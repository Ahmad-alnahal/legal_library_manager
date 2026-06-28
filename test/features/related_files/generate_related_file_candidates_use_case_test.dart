// test/features/related_files/generate_related_file_candidates_use_case_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/features/related_files/application/generate_related_file_candidates_use_case.dart';
import 'package:legal_library_manager/features/related_files/domain/entities/candidate_file_info.dart';
import 'package:legal_library_manager/features/related_files/domain/entities/candidate_reason.dart';

import 'support/related_file_fakes.dart';

GenerateRelatedFileCandidatesUseCase _buildUseCase(
  FakeRelatedFileCandidateRepository repo,
) => GenerateRelatedFileCandidatesUseCase(
  candidateRepository: repo,
  clock: const SystemClock(),
);

CandidateFileInfo _file({
  required int fileId,
  required int documentId,
  required String path,
  required String ext,
  String? sha256Hash,
  String? documentTitle,
}) => CandidateFileInfo(
  fileId: fileId,
  documentId: documentId,
  absolutePath: path,
  extension: ext,
  sha256Hash: sha256Hash,
  documentTitle: documentTitle,
);

void main() {
  // ── Test 1: empty input ───────────────────────────────────────────────────────
  test('empty file list returns all-zero result', () async {
    final repo = FakeRelatedFileCandidateRepository();
    final result = await _buildUseCase(repo).call([]);

    expect(result.comparedPairCount, 0);
    expect(result.generatedCandidateCount, 0);
    expect(result.insertedCount, 0);
    expect(result.skippedLargeBucketCount, 0);
    expect(repo.inserted, isEmpty);
  });

  // ── Test 2: single file — no pairs ───────────────────────────────────────────
  test('single file produces no pairs', () async {
    final repo = FakeRelatedFileCandidateRepository();
    final result = await _buildUseCase(repo).call([
      _file(
        fileId: 1,
        documentId: 1,
        path: r'C:\legal\contract.pdf',
        ext: '.pdf',
      ),
    ]);

    expect(result.comparedPairCount, 0);
    expect(result.insertedCount, 0);
  });

  // ── Test 3: two files, shared token, different documents ─────────────────────
  test(
    'two files with shared token and different documentId produce a candidate',
    () async {
      final repo = FakeRelatedFileCandidateRepository();
      final result = await _buildUseCase(repo).call([
        _file(
          fileId: 1,
          documentId: 1,
          path: r'C:\docs\contract_2024.pdf',
          ext: '.pdf',
        ),
        _file(
          fileId: 2,
          documentId: 2,
          path: r'C:\docs\contract_2024.doc',
          ext: '.doc',
        ),
      ]);

      expect(result.generatedCandidateCount, 1);
      expect(result.insertedCount, 1);
      expect(repo.inserted, hasLength(1));
      // canonical ordering: smaller ID first
      expect(repo.inserted.first.fileAId, 1);
      expect(repo.inserted.first.fileBId, 2);
    },
  );

  // ── Test 4: same documentId — excluded ───────────────────────────────────────
  test('pair sharing documentId is excluded', () async {
    final repo = FakeRelatedFileCandidateRepository();
    final result = await _buildUseCase(repo).call([
      _file(
        fileId: 1,
        documentId: 42,
        path: r'C:\docs\contract.pdf',
        ext: '.pdf',
      ),
      _file(
        fileId: 2,
        documentId: 42,
        path: r'C:\docs\contract.doc',
        ext: '.doc',
      ),
    ]);

    expect(result.comparedPairCount, 0);
    expect(result.insertedCount, 0);
  });

  // ── Test 5: same non-null sha256Hash — excluded ──────────────────────────────
  test(
    'pair sharing non-null sha256Hash is excluded (exact duplicate)',
    () async {
      const sha =
          'aabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccddaabbccdd';
      final repo = FakeRelatedFileCandidateRepository();
      await _buildUseCase(repo).call([
        _file(
          fileId: 1,
          documentId: 1,
          path: r'C:\docs\report.pdf',
          ext: '.pdf',
          sha256Hash: sha,
        ),
        _file(
          fileId: 2,
          documentId: 2,
          path: r'C:\docs\report_copy.pdf',
          ext: '.pdf',
          sha256Hash: sha,
        ),
      ]);

      expect(repo.inserted, isEmpty);
    },
  );

  // ── Test 6: .doc + .pdf with shared token → docPdfPair reason ────────────────
  test('.doc + .pdf pair with shared token gets docPdfPair reason', () async {
    final repo = FakeRelatedFileCandidateRepository();
    await _buildUseCase(repo).call([
      _file(
        fileId: 1,
        documentId: 1,
        path: r'C:\src\legislation_2020.pdf',
        ext: '.pdf',
      ),
      _file(
        fileId: 2,
        documentId: 2,
        path: r'C:\src\legislation_2020.doc',
        ext: '.doc',
      ),
    ]);

    expect(repo.inserted, hasLength(1));
    expect(repo.inserted.first.reason, CandidateReason.docPdfPair);
  });

  // ── Test 7: .doc + .pdf with NO shared token — no candidate ──────────────────
  test(
    '.doc + .pdf with no shared significant token produces no candidate',
    () async {
      final repo = FakeRelatedFileCandidateRepository();
      await _buildUseCase(repo).call([
        _file(
          fileId: 1,
          documentId: 1,
          path: r'C:\a\zebra_finance.pdf',
          ext: '.pdf',
        ),
        _file(
          fileId: 2,
          documentId: 2,
          path: r'C:\b\moon_report.doc',
          ext: '.doc',
        ),
      ]);

      expect(repo.inserted, isEmpty);
    },
  );

  // ── Test 8: same directory + shared tokens → nearFolderBasename ──────────────
  test(
    'same directory and shared tokens gives nearFolderBasename reason',
    () async {
      final repo = FakeRelatedFileCandidateRepository();
      // Files share tokens [contract, legal] → bucket key "contract|legal" is shared.
      // Both are .pdf (not .doc), so reason must be nearFolderBasename, not docPdfPair.
      await _buildUseCase(repo).call([
        _file(
          fileId: 1,
          documentId: 1,
          path: r'C:\legal\contract_legal_v1.pdf',
          ext: '.pdf',
        ),
        _file(
          fileId: 2,
          documentId: 2,
          path: r'C:\legal\contract_legal_v2.pdf',
          ext: '.pdf',
        ),
      ]);

      expect(repo.inserted, hasLength(1));
      expect(repo.inserted.first.reason, CandidateReason.nearFolderBasename);
    },
  );

  // ── Test 9: title null — no title bonus applied ───────────────────────────────
  test('title bonus is not applied when documentTitle is null', () async {
    final repo = FakeRelatedFileCandidateRepository();
    await _buildUseCase(repo).call([
      _file(
        fileId: 1,
        documentId: 1,
        path: r'C:\a\report_annual.pdf',
        ext: '.pdf',
        documentTitle: null,
      ),
      _file(
        fileId: 2,
        documentId: 2,
        path: r'C:\b\report_annual.doc',
        ext: '.doc',
        documentTitle: null,
      ),
    ]);

    // A pair may be generated (doc+pdf with shared token), but reason must not
    // be titleSimilarity since title was null.
    if (repo.inserted.isNotEmpty) {
      expect(
        repo.inserted.first.reason,
        isNot(CandidateReason.titleSimilarity),
      );
    }
  });

  // ── Test 10: title similarity boosts confidence after bucket discovery ────────
  test(
    'shared title tokens boost confidence for a pair already in the same bucket',
    () async {
      final repo = FakeRelatedFileCandidateRepository();
      await _buildUseCase(repo).call([
        _file(
          fileId: 1,
          documentId: 1,
          path: r'C:\a\legislation.pdf',
          ext: '.pdf',
          documentTitle: 'قانون العمل الموحد',
        ),
        _file(
          fileId: 2,
          documentId: 2,
          path: r'C:\b\legislation.doc',
          ext: '.doc',
          documentTitle: 'قانون العمل الموحد',
        ),
      ]);

      // doc+pdf with shared token — should be generated with title boost.
      expect(repo.inserted, hasLength(1));
      // Confidence should exceed a pure filename-only score.
      expect(repo.inserted.first.confidence, greaterThan(0.30));
    },
  );

  // ── Test 11: confidence below threshold — pair dropped ───────────────────────
  test('pair with confidence below 0.20 is not generated', () async {
    final repo = FakeRelatedFileCandidateRepository();
    // Both purely numeric tokens — should produce no significant tokens after
    // filtering (numbers stripped), so no shared bucket and no candidate.
    await _buildUseCase(repo).call([
      _file(fileId: 1, documentId: 1, path: r'C:\x\12345.pdf', ext: '.pdf'),
      _file(fileId: 2, documentId: 2, path: r'C:\y\67890.pdf', ext: '.pdf'),
    ]);

    expect(repo.inserted, isEmpty);
  });

  // ── Test 12: large bucket is skipped ─────────────────────────────────────────
  test('bucket with more than 50 files is skipped', () async {
    final repo = FakeRelatedFileCandidateRepository();
    // 51 files all sharing the same single significant token "contract".
    final files = List.generate(
      51,
      (i) => _file(
        fileId: i + 1,
        documentId: i + 1,
        path: 'C:\\docs\\contract_${i + 1}.pdf',
        ext: '.pdf',
      ),
    );

    final result = await _buildUseCase(repo).call(files);

    expect(result.skippedLargeBucketCount, greaterThanOrEqualTo(1));
    expect(result.comparedPairCount, 0);
    expect(repo.inserted, isEmpty);
  });

  // ── Test 13: cross-bucket pair deduplication ──────────────────────────────────
  test('pair reachable via two shared bucket keys is counted once', () async {
    final repo = FakeRelatedFileCandidateRepository();
    // Both files share the same multi-token filename → multiple shared bucket keys.
    await _buildUseCase(repo).call([
      _file(
        fileId: 1,
        documentId: 1,
        path: r'C:\a\alpha_beta_gamma.pdf',
        ext: '.pdf',
      ),
      _file(
        fileId: 2,
        documentId: 2,
        path: r'C:\b\alpha_beta_gamma.doc',
        ext: '.doc',
      ),
    ]);

    // Despite sharing multiple buckets, pair must be inserted exactly once.
    expect(repo.inserted, hasLength(1));
  });

  // ── Test 14: idempotency ──────────────────────────────────────────────────────
  test(
    'running the use case twice: second run insertedCount=0 but generatedCandidateCount unchanged',
    () async {
      final repo = FakeRelatedFileCandidateRepository();
      final useCase = _buildUseCase(repo);
      final files = [
        _file(
          fileId: 1,
          documentId: 1,
          path: r'C:\docs\contract_2024.pdf',
          ext: '.pdf',
        ),
        _file(
          fileId: 2,
          documentId: 2,
          path: r'C:\docs\contract_2024.doc',
          ext: '.doc',
        ),
      ];

      final first = await useCase.call(files);
      final second = await useCase.call(files);

      expect(first.generatedCandidateCount, greaterThan(0));
      expect(second.generatedCandidateCount, first.generatedCandidateCount);
      expect(second.insertedCount, 0);
    },
  );
}
