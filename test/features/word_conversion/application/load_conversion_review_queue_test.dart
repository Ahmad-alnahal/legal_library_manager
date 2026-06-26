// test/features/word_conversion/application/load_conversion_review_queue_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/word_conversion/application/load_conversion_review_queue.dart';
import 'package:legal_library_manager/features/word_conversion/domain/entities/conversion_execution_record.dart';
import 'package:legal_library_manager/features/word_conversion/domain/entities/conversion_review_item.dart';
import 'package:legal_library_manager/features/word_conversion/domain/entities/conversion_work_item.dart';
import 'package:legal_library_manager/features/word_conversion/domain/entities/word_conversion_record.dart';
import 'package:legal_library_manager/features/word_conversion/domain/entities/word_source_record.dart';
import 'package:legal_library_manager/features/word_conversion/domain/repositories/word_conversion_repository.dart';

// ── Test doubles ──────────────────────────────────────────────────────────────

class _FakeRepository implements WordConversionRepository {
  List<ConversionReviewItem> pendingReviews = [];
  bool loadThrows = false;

  @override
  Future<List<ConversionReviewItem>> loadPendingConversionReviews() async {
    if (loadThrows) throw Exception('db error');
    return pendingReviews;
  }

  // Unused methods — stubs satisfy the interface.
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
  Future<bool> approveConversionReview({
    required int conversionId,
    required String nowIso,
  }) => throw UnimplementedError();
  @override
  Future<bool> rejectConversionReview({
    required int conversionId,
    required String nowIso,
    String? reviewNote,
  }) => throw UnimplementedError();
  @override
  Future<List<ConversionWorkItem>> loadConversionWorkQueue() =>
      throw UnimplementedError();
  @override
  Future<String> allocateDocumentCode(int documentId) =>
      throw UnimplementedError();
}

const _kItem = ConversionReviewItem(
  conversionId: 1,
  documentId: 10,
  sourceFileId: 2,
  outputFileId: 3,
  sourceFileName: 'contract.doc',
  sourcePath: r'C:\sources\contract.doc',
  outputFileName: 'deadbeef.pdf',
  outputPath: r'C:\Library\WordOutput\deadbeef.pdf',
  createdAt: '2026-06-25T10:00:00.000Z',
);

void main() {
  late _FakeRepository repo;
  late LoadConversionReviewQueue useCase;

  setUp(() {
    repo = _FakeRepository();
    useCase = LoadConversionReviewQueue(repository: repo);
  });

  group('LoadConversionReviewQueue', () {
    test('returns empty list when queue is empty', () async {
      repo.pendingReviews = [];
      final result = await useCase();
      expect(result, isEmpty);
    });

    test('returns list of pending items', () async {
      repo.pendingReviews = [_kItem];
      final result = await useCase();
      expect(result, hasLength(1));
      expect(result.first.conversionId, 1);
      expect(result.first.sourceFileName, 'contract.doc');
      expect(result.first.outputFileName, 'deadbeef.pdf');
    });

    test('propagates repository exceptions to caller', () async {
      repo.loadThrows = true;
      expect(() => useCase(), throwsException);
    });

    test('ordering is preserved from repository (newest-first)', () async {
      final older = ConversionReviewItem(
        conversionId: 1,
        documentId: 10,
        sourceFileId: 2,
        outputFileId: 3,
        sourceFileName: 'old.doc',
        sourcePath: r'C:\sources\old.doc',
        outputFileName: 'aaa.pdf',
        outputPath: r'C:\Library\WordOutput\aaa.pdf',
        createdAt: '2026-06-24T08:00:00.000Z',
      );
      final newer = ConversionReviewItem(
        conversionId: 2,
        documentId: 11,
        sourceFileId: 4,
        outputFileId: 5,
        sourceFileName: 'new.doc',
        sourcePath: r'C:\sources\new.doc',
        outputFileName: 'bbb.pdf',
        outputPath: r'C:\Library\WordOutput\bbb.pdf',
        createdAt: '2026-06-25T10:00:00.000Z',
      );
      repo.pendingReviews = [newer, older]; // repository returns newest first
      final result = await useCase();
      expect(result.first.conversionId, 2);
      expect(result.last.conversionId, 1);
    });
  });
}
