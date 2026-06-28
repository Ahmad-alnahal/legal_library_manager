// test/features/related_files/candidate_generation_stress_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/features/related_files/application/generate_related_file_candidates_use_case.dart';
import 'package:legal_library_manager/features/related_files/domain/entities/candidate_file_info.dart';

import 'support/related_file_fakes.dart';

void main() {
  GenerateRelatedFileCandidatesUseCase buildUseCase() =>
      GenerateRelatedFileCandidatesUseCase(
        candidateRepository: FakeRelatedFileCandidateRepository(),
        clock: const SystemClock(),
      );

  // 50-word vocabulary of meaningful Arabic + English legal terms.
  const List<String> vocab = [
    'contract',
    'agreement',
    'legislation',
    'decree',
    'judgment',
    'ruling',
    'petition',
    'claim',
    'appeal',
    'settlement',
    'regulation',
    'ordinance',
    'statute',
    'code',
    'charter',
    'protocol',
    'memorandum',
    'certificate',
    'license',
    'permit',
    'عقد',
    'اتفاقية',
    'حكم',
    'قرار',
    'لائحة',
    'نظام',
    'مرسوم',
    'قانون',
    'شهادة',
    'رخصة',
    'دعوى',
    'استئناف',
    'تسوية',
    'بروتوكول',
    'مذكرة',
    'تقرير',
    'طلب',
    'إخطار',
    'قضية',
    'ملف',
    'annual',
    'report',
    'final',
    'draft',
    'review',
    'revised',
    'official',
    'legal',
    'signed',
    'certified',
  ];

  CandidateFileInfo realisticFile(int id, int seed) {
    final t1 = vocab[seed % vocab.length];
    final t2 = vocab[(seed * 3 + 7) % vocab.length];
    final t3 = vocab[(seed * 7 + 13) % vocab.length];
    final name = '${t1}_${t2}_${t3}_$seed';
    final ext = seed.isEven ? '.pdf' : '.doc';
    return CandidateFileInfo(
      fileId: id,
      documentId: id,
      absolutePath: 'C:\\legal\\$name$ext',
      extension: ext,
    );
  }

  // ── Scenario 1: realistic vocabulary, bounded comparisons ────────────────────
  test(
    '500 files with 50-word vocabulary: comparisons are bounded (not O(N²))',
    () async {
      final files = List.generate(500, (i) => realisticFile(i + 1, i));
      final result = await buildUseCase().call(files);

      expect(
        result.comparedPairCount,
        lessThan(500 * 150),
        reason: 'comparisons must be bounded (O(N*K), not O(N²))',
      );
      expect(
        result.skippedLargeBucketCount,
        0,
        reason: 'realistic 50-word vocab should not produce oversized buckets',
      );
    },
  );

  // ── Scenario 2: degenerate single bucket — skipped ───────────────────────────
  test(
    '500 files all sharing identical single-token name: bucket is skipped',
    () async {
      final files = List.generate(
        500,
        (i) => CandidateFileInfo(
          fileId: i + 1,
          documentId: i + 1,
          absolutePath: 'C:\\docs\\contract_${i + 1}.pdf',
          extension: '.pdf',
        ),
      );

      final result = await buildUseCase().call(files);

      expect(result.skippedLargeBucketCount, greaterThanOrEqualTo(1));
      expect(result.comparedPairCount, 0);
    },
  );

  // ── Scenario 3: all-unique single-token names — no comparisons ───────────────
  test(
    '500 files with unique single-token names: comparedPairCount = 0',
    () async {
      final files = List.generate(
        500,
        (i) => CandidateFileInfo(
          fileId: i + 1,
          documentId: i + 1,
          absolutePath:
              'C:\\docs\\uniquefile${i.toString().padLeft(4, '0')}.pdf',
          extension: '.pdf',
        ),
      );

      final result = await buildUseCase().call(files);

      expect(result.comparedPairCount, 0);
      expect(result.insertedCount, 0);
    },
  );
}
