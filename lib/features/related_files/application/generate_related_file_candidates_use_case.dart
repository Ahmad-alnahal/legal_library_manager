// lib/features/related_files/application/generate_related_file_candidates_use_case.dart
// ignore_for_file: prefer_initializing_formals

import 'package:path/path.dart' as p;

import '../../../core/time/clock.dart';
import '../domain/entities/candidate_file_info.dart';
import '../domain/entities/candidate_input.dart';
import '../domain/entities/candidate_reason.dart';
import '../domain/repositories/related_file_candidate_repository.dart';
import 'related_candidate_generation_result.dart';

/// Generates related-file candidate pairs using a bucketed filename-token
/// algorithm.
///
/// **Algorithm:**
/// 1. Extract significant tokens from each file's basename (lower-cased,
///    stopwords and numbers removed).
/// 2. Generate up to 3 bucket keys per file from consecutive sorted token pairs.
/// 3. Group files by bucket key; skip buckets larger than [maxBucketSize].
/// 4. Within each bucket generate all pairs (A, B) where A.fileId < B.fileId,
///    excluding same-document pairs and exact-hash pairs.
/// 5. Deduplicate pairs seen via multiple shared bucket keys.
/// 6. Score each pair; drop those below [minConfidence].
/// 7. Upsert surviving pairs (INSERT OR IGNORE — existing pairs preserved).
///
/// **Safety:** never reads, writes, moves, or deletes source files. Never
/// modifies document records, workflow statuses, or duplicate groups.
class GenerateRelatedFileCandidatesUseCase {
  const GenerateRelatedFileCandidatesUseCase({
    required RelatedFileCandidateRepository candidateRepository,
    required Clock clock,
  }) : _candidateRepository = candidateRepository,
       _clock = clock;

  final RelatedFileCandidateRepository _candidateRepository;
  final Clock _clock;

  /// Maximum files per bucket. Buckets exceeding this are skipped (too generic).
  static const int maxBucketSize = 50;

  /// Minimum confidence score for a pair to become a candidate.
  static const double minConfidence = 0.20;

  static const Set<String> _stopWords = {
    // Arabic function words
    'في', 'من', 'على', 'إلى', 'عن', 'مع', 'هذا', 'هذه', 'ذلك',
    'هو', 'هي', 'أن', 'لا', 'ما', 'كان', 'كانت', 'قد', 'لم', 'بعد',
    // English function words (mixed filenames)
    'the', 'of', 'and', 'to', 'in', 'for', 'on', 'at',
  };

  Future<RelatedCandidateGenerationResult> call(
    List<CandidateFileInfo> files,
  ) async {
    if (files.isEmpty) {
      return const RelatedCandidateGenerationResult(
        comparedPairCount: 0,
        generatedCandidateCount: 0,
        insertedCount: 0,
        skippedLargeBucketCount: 0,
      );
    }

    // Step 1 & 2: compute tokens and bucket keys per file.
    final fileTokens = <int, List<String>>{};
    final bucketToFiles = <String, List<CandidateFileInfo>>{};

    for (final f in files) {
      final tokens = _extractTokens(f.absolutePath);
      fileTokens[f.fileId] = tokens;
      for (final key in _bucketKeys(tokens)) {
        bucketToFiles.putIfAbsent(key, () => []).add(f);
      }
    }

    // Step 3–5: generate pairs per bucket, deduplicated.
    int comparedPairCount = 0;
    int skippedLargeBucketCount = 0;
    final seenPairs = <String>{};
    final candidateInputs = <CandidateInput>[];

    for (final bucket in bucketToFiles.values) {
      if (bucket.length > maxBucketSize) {
        skippedLargeBucketCount++;
        continue;
      }
      for (int i = 0; i < bucket.length; i++) {
        for (int j = i + 1; j < bucket.length; j++) {
          final a = bucket[i];
          final b = bucket[j];
          final minId = a.fileId < b.fileId ? a.fileId : b.fileId;
          final maxId = a.fileId < b.fileId ? b.fileId : a.fileId;
          final pairKey = '$minId:$maxId';

          // Deduplicate across bucket keys.
          if (!seenPairs.add(pairKey)) continue;

          // Same-document exclusion.
          if (a.documentId == b.documentId) continue;

          // Exact-hash exclusion.
          if (a.sha256Hash != null && a.sha256Hash == b.sha256Hash) continue;

          comparedPairCount++;

          final fileA = a.fileId < b.fileId ? a : b;
          final fileB = a.fileId < b.fileId ? b : a;

          final (confidence, reason) = _score(fileA, fileB, fileTokens);
          if (confidence < minConfidence) continue;

          candidateInputs.add(
            CandidateInput(
              fileAId: minId,
              fileBId: maxId,
              reason: reason,
              confidence: confidence,
            ),
          );
        }
      }
    }

    final generatedCandidateCount = candidateInputs.length;
    final insertedCount = candidateInputs.isEmpty
        ? 0
        : await _candidateRepository.upsertCandidates(
            candidateInputs,
            _clock.nowUtc(),
          );

    return RelatedCandidateGenerationResult(
      comparedPairCount: comparedPairCount,
      generatedCandidateCount: generatedCandidateCount,
      insertedCount: insertedCount,
      skippedLargeBucketCount: skippedLargeBucketCount,
    );
  }

  // ── Token helpers ────────────────────────────────────────────────────────────

  static List<String> _extractTokens(String absolutePath) {
    final base = p.basenameWithoutExtension(absolutePath).toLowerCase();
    final raw = base.split(RegExp(r'[\s\-_\.،,؛؟!\(\)\[\]]+'));
    final significant =
        raw
            .where(
              (t) =>
                  t.length >= 2 &&
                  !RegExp(r'^\d+$').hasMatch(t) &&
                  !_stopWords.contains(t),
            )
            .toList()
          ..sort();
    return significant;
  }

  static List<String> _bucketKeys(List<String> tokens) {
    if (tokens.isEmpty) return const [];
    if (tokens.length == 1) return [tokens[0]];
    final keys = <String>[];
    if (tokens.length >= 2) keys.add('${tokens[0]}|${tokens[1]}');
    if (tokens.length >= 3) {
      keys.add('${tokens[1]}|${tokens[2]}');
      keys.add('${tokens[0]}|${tokens[2]}');
    }
    return keys;
  }

  // ── Confidence scoring ───────────────────────────────────────────────────────

  static (double, CandidateReason) _score(
    CandidateFileInfo a,
    CandidateFileInfo b,
    Map<int, List<String>> fileTokens,
  ) {
    final tokensA = fileTokens[a.fileId] ?? const [];
    final tokensB = fileTokens[b.fileId] ?? const [];

    final setA = tokensA.toSet();
    final setB = tokensB.toSet();
    final shared = setA.intersection(setB).length;
    final union = setA.union(setB).length;
    final jaccard = union == 0 ? 0.0 : shared / union;

    double score = jaccard;

    // Same directory bonus.
    final dirA = p.dirname(a.absolutePath);
    final dirB = p.dirname(b.absolutePath);
    if (dirA == dirB) {
      score += 0.15;
    } else if (p.dirname(dirA) == p.dirname(dirB)) {
      score += 0.05;
    }

    // Cross-extension .doc + .pdf bonus (requires ≥1 shared token).
    final extA = a.extension.toLowerCase();
    final extB = b.extension.toLowerCase();
    final isDocPdfPair =
        (extA == '.doc' && extB == '.pdf') ||
        (extA == '.pdf' && extB == '.doc');
    if (isDocPdfPair && shared >= 1) {
      score += 0.25;
    }

    // Title similarity boost (bucket discovery only; no title-only discovery).
    double titleBoost = 0.0;
    if (a.documentTitle != null && b.documentTitle != null) {
      final titleA = _extractTitleTokens(a.documentTitle!);
      final titleB = _extractTitleTokens(b.documentTitle!);
      final sharedTitle = titleA.toSet().intersection(titleB.toSet()).length;
      if (sharedTitle >= 2) {
        titleBoost = 0.15;
        score += titleBoost;
      }
    }

    final confidence = score.clamp(0.0, 1.0);

    // Reason: first matching rule.
    final CandidateReason reason;
    if (isDocPdfPair && shared >= 1) {
      reason = CandidateReason.docPdfPair;
    } else if (dirA == dirB) {
      reason = CandidateReason.nearFolderBasename;
    } else if (titleBoost > 0 && jaccard < minConfidence) {
      reason = CandidateReason.titleSimilarity;
    } else {
      reason = CandidateReason.similarBasename;
    }

    return (confidence, reason);
  }

  static List<String> _extractTitleTokens(String title) {
    final raw = title.toLowerCase().split(RegExp(r'[\s\-_\.،,؛؟!\(\)\[\]]+'));
    return raw
        .where(
          (t) =>
              t.length >= 2 &&
              !RegExp(r'^\d+$').hasMatch(t) &&
              !_stopWords.contains(t),
        )
        .toList();
  }
}
