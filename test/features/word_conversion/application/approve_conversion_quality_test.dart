// test/features/word_conversion/application/approve_conversion_quality_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/features/word_conversion/application/approve_conversion_quality.dart';
import 'package:legal_library_manager/features/word_conversion/domain/entities/conversion_execution_record.dart';
import 'package:legal_library_manager/features/word_conversion/domain/entities/conversion_review_action_result.dart';
import 'package:legal_library_manager/features/word_conversion/domain/entities/conversion_review_item.dart';
import 'package:legal_library_manager/features/word_conversion/domain/entities/conversion_work_item.dart';
import 'package:legal_library_manager/features/word_conversion/domain/entities/word_conversion_record.dart';
import 'package:legal_library_manager/features/word_conversion/domain/entities/word_source_record.dart';
import 'package:legal_library_manager/features/word_conversion/domain/repositories/word_conversion_repository.dart';

// ── Test doubles ──────────────────────────────────────────────────────────────

class _FakeRepository implements WordConversionRepository {
  bool approveReturn = true;
  bool approveThrows = false;
  int? lastConversionId;
  String? lastNowIso;

  @override
  Future<bool> approveConversionReview({
    required int conversionId,
    required String nowIso,
  }) async {
    lastConversionId = conversionId;
    lastNowIso = nowIso;
    if (approveThrows) throw Exception('db error');
    return approveReturn;
  }

  // Unused stubs.
  @override
  Future<String?> loadManagedLibraryRoot() => throw UnimplementedError();
  @override
  Future<WordSourceRecord?> loadSourceRecord(int fileId) =>
      throw UnimplementedError();
  @override
  Future<WordConversionRecord?> findActiveConversion(int sourceFileId) =>
      throw UnimplementedError();
  @override
  Future<int> persistConversionRecord({
    required int documentId,
    required int sourceFileId,
    required String converterKey,
    required String operationId,
    required String nowIso,
  }) => throw UnimplementedError();
  @override
  Future<ConversionExecutionRecord?> loadConversionForExecution(
    int conversionId,
  ) => throw UnimplementedError();
  @override
  Future<bool> markConverting(int conversionId, String nowIso) =>
      throw UnimplementedError();
  @override
  Future<int> finalizeSuccessfulConversion({
    required int conversionId,
    required int documentId,
    required int sourceFileId,
    required String outputPath,
    required String outputFileName,
    required String pdfSha256,
    required int fileSizeBytes,
    required String operationId,
    required String nowIso,
  }) => throw UnimplementedError();
  @override
  Future<void> recordFailedConversion({
    required int conversionId,
    required int documentId,
    required int sourceFileId,
    required String errorCode,
    required String errorMessageSafe,
    required String operationId,
    required String nowIso,
  }) => throw UnimplementedError();
  @override
  Future<List<ConversionReviewItem>> loadPendingConversionReviews() =>
      throw UnimplementedError();
  @override
  Future<List<ConversionWorkItem>> loadConversionWorkQueue() =>
      throw UnimplementedError();
  @override
  Future<bool> rejectConversionReview({
    required int conversionId,
    required String nowIso,
    String? reviewNote,
  }) => throw UnimplementedError();
  @override
  Future<String> allocateDocumentCode(int documentId) =>
      throw UnimplementedError();
}

class _FakeClock extends Clock {
  const _FakeClock(this._fixed);
  final DateTime _fixed;
  @override
  DateTime nowUtc() => _fixed;
}

void main() {
  late _FakeRepository repo;
  late ApproveConversionQuality useCase;
  final fixedNow = DateTime.utc(2026, 6, 25, 12, 0, 0);

  setUp(() {
    repo = _FakeRepository();
    useCase = ApproveConversionQuality(
      repository: repo,
      clock: _FakeClock(fixedNow),
    );
  });

  group('ApproveConversionQuality', () {
    test('returns success when repository update succeeds', () async {
      repo.approveReturn = true;
      final result = await useCase(1);
      expect(result, isA<ConversionReviewActionSuccess>());
    });

    test('passes the conversion ID to the repository', () async {
      await useCase(42);
      expect(repo.lastConversionId, 42);
    });

    test('passes the clock timestamp to the repository', () async {
      await useCase(1);
      expect(repo.lastNowIso, fixedNow.toIso8601String());
    });

    test(
      'returns NotReviewable when row was not in reviewable state',
      () async {
        repo.approveReturn = false;
        final result = await useCase(1);
        expect(result, isA<ConversionReviewActionNotReviewable>());
      },
    );

    test('returns Failed when repository throws', () async {
      repo.approveThrows = true;
      final result = await useCase(1);
      expect(result, isA<ConversionReviewActionFailed>());
      final failed = result as ConversionReviewActionFailed;
      expect(failed.safeMessage, isNotEmpty);
    });
  });
}
