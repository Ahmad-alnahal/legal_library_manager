// test/features/word_conversion/application/stage_word_source_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/core/time/clock.dart';
import 'package:legal_library_manager/features/word_conversion/application/stage_word_source.dart';
import 'package:legal_library_manager/features/word_conversion/domain/entities/conversion_execution_record.dart';
import 'package:legal_library_manager/features/word_conversion/domain/entities/conversion_review_item.dart';
import 'package:legal_library_manager/features/word_conversion/domain/entities/conversion_work_item.dart';
import 'package:legal_library_manager/features/word_conversion/domain/entities/word_conversion_record.dart';
import 'package:legal_library_manager/features/word_conversion/domain/entities/word_staging_error.dart';
import 'package:legal_library_manager/features/word_conversion/domain/entities/word_staging_result.dart';
import 'package:legal_library_manager/features/word_conversion/domain/entities/word_source_record.dart';
import 'package:legal_library_manager/features/word_conversion/domain/repositories/word_conversion_repository.dart';
import 'package:legal_library_manager/features/word_conversion/domain/services/word_staging_filesystem.dart';

// ── Test doubles ─────────────────────────────────────────────────────────────

class _FakeRepository implements WordConversionRepository {
  String? managedLibraryRoot;
  WordSourceRecord? sourceRecord;
  WordConversionRecord? activeConversion;
  int nextConversionId = 42;
  bool persistThrows = false;

  @override
  Future<String?> loadManagedLibraryRoot() async => managedLibraryRoot;

  @override
  Future<WordSourceRecord?> loadSourceRecord(int fileId) async => sourceRecord;

  @override
  Future<WordConversionRecord?> findActiveConversion(int sourceFileId) async =>
      activeConversion;

  @override
  Future<int> persistConversionRecord({
    required int documentId,
    required int sourceFileId,
    required String converterKey,
    required String operationId,
    required String nowIso,
  }) async {
    if (persistThrows) throw Exception('db error');
    return nextConversionId;
  }

  // P1.3 methods — not called by StageWordSource; stubs satisfy the interface.
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

  // P1.4 review methods — not called by StageWordSource; stubs satisfy the interface.
  @override
  Future<List<ConversionReviewItem>> loadPendingConversionReviews() =>
      throw UnimplementedError();

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

class _FakeFilesystem implements WordStagingFilesystem {
  bool ensureDirectoryFails = false;
  bool copyToTempFails = false;
  bool finalizeFails = false;
  bool stagedFileExists = false;

  List<String> deletedTempPaths = [];

  @override
  Future<StagingOperationResult> ensureStagingDirectory(
    String stagingDir,
  ) async {
    if (ensureDirectoryFails) {
      return const StagingFailure(safeMessage: 'test directory failure');
    }
    return const StagingSuccess();
  }

  @override
  Future<StagingOperationResult> copyToTemp(
    String sourcePath,
    String tempDestPath,
  ) async {
    if (copyToTempFails) {
      return const StagingFailure(safeMessage: 'test copy failure');
    }
    return const StagingSuccess();
  }

  @override
  Future<StagingOperationResult> finalize(
    String tempPath,
    String finalPath,
  ) async {
    if (finalizeFails) {
      return const StagingFailure(safeMessage: 'test finalize failure');
    }
    return const StagingSuccess();
  }

  @override
  Future<StagingOperationResult> deleteTempSafe(
    String tempPath,
    String stagingDir,
  ) async {
    deletedTempPaths.add(tempPath);
    return const StagingSuccess();
  }

  @override
  bool isExistingFile(String path) => stagedFileExists;

  @override
  Future<StagingOperationResult> deleteStagedFileSafe(
    String path,
    String stagingDir,
  ) async => const StagingSuccess();
}

class _FakeClock extends Clock {
  const _FakeClock(this._fixed);
  final DateTime _fixed;
  @override
  DateTime nowUtc() => _fixed;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

WordSourceRecord _validDoc({
  int fileId = 1,
  int documentId = 10,
  String absolutePath = r'C:\sources\contract.doc',
  String extension = '.doc',
  String? sha256Hash = 'abc123',
  String fileHealthKey = 'healthy',
  String fileRoleKey = 'source_original',
}) {
  return WordSourceRecord(
    fileId: fileId,
    documentId: documentId,
    absolutePath: absolutePath,
    extension: extension,
    sha256Hash: sha256Hash,
    fileHealthKey: fileHealthKey,
    fileRoleKey: fileRoleKey,
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late _FakeRepository repo;
  late _FakeFilesystem fs;
  late StageWordSource useCase;

  const String fakeRoot = r'C:\Library';
  final DateTime fixedNow = DateTime.utc(2026, 6, 25, 10, 0, 0);

  setUp(() {
    repo = _FakeRepository()
      ..managedLibraryRoot = fakeRoot
      ..sourceRecord = _validDoc();
    fs = _FakeFilesystem();
    useCase = StageWordSource(
      repository: repo,
      filesystem: fs,
      clock: _FakeClock(fixedNow),
    );
  });

  group('StageWordSource – happy path', () {
    test('returns WordStagingSuccess with correct conversionId', () async {
      repo.nextConversionId = 7;

      final result = await useCase.call(1);

      expect(result, isA<WordStagingSuccess>());
      expect((result as WordStagingSuccess).conversionId, 7);
    });

    test(
      'staged path is content-addressed: sha256 + extension inside WordStaging dir',
      () async {
        final result = await useCase.call(1);

        expect(result, isA<WordStagingSuccess>());
        final success = result as WordStagingSuccess;
        expect(success.stagedPath, contains('WordStaging'));
        expect(success.stagedPath, contains('abc123'));
        expect(success.stagedPath, endsWith('.doc'));
      },
    );

    test(
      'skips copy when staged file already exists on disk (recovery)',
      () async {
        fs.stagedFileExists = true;

        final result = await useCase.call(1);

        expect(result, isA<WordStagingSuccess>());
        // No temp file was deleted (copy was skipped entirely).
        expect(fs.deletedTempPaths, isEmpty);
      },
    );
  });

  group('StageWordSource – idempotency', () {
    test(
      'returns WordStagingAlreadyStaged when active conversion exists',
      () async {
        repo.activeConversion = const WordConversionRecord(
          conversionId: 99,
          statusKey: 'pending_conversion',
        );

        final result = await useCase.call(1);

        expect(result, isA<WordStagingAlreadyStaged>());
        expect((result as WordStagingAlreadyStaged).conversionId, 99);
      },
    );

    test('already-staged result carries the derived staged path', () async {
      repo.activeConversion = const WordConversionRecord(
        conversionId: 5,
        statusKey: 'pending_conversion',
      );

      final result = await useCase.call(1);

      final staged = result as WordStagingAlreadyStaged;
      expect(staged.stagedPath, contains('WordStaging'));
      expect(staged.stagedPath, contains('abc123'));
      expect(staged.stagedPath, endsWith('.doc'));
    });
  });

  group('StageWordSource – pre-flight blocks', () {
    test('blocks when source record does not exist', () async {
      repo.sourceRecord = null;

      final result = await useCase.call(99);

      expect(result, isA<WordStagingBlocked>());
      expect(
        (result as WordStagingBlocked).error,
        WordStagingError.sourceFileNotFound,
      );
    });

    test('blocks when file role is not source_original', () async {
      repo.sourceRecord = _validDoc(fileRoleKey: 'managed_copy');

      final result = await useCase.call(1);

      expect(result, isA<WordStagingBlocked>());
      expect(
        (result as WordStagingBlocked).error,
        WordStagingError.sourceFileNotWordDocument,
      );
    });

    test('blocks when extension is not .doc', () async {
      repo.sourceRecord = _validDoc(extension: '.pdf');

      final result = await useCase.call(1);

      expect(result, isA<WordStagingBlocked>());
      expect(
        (result as WordStagingBlocked).error,
        WordStagingError.sourceFileNotWordDocument,
      );
    });

    test('blocks when sha256 hash is null', () async {
      repo.sourceRecord = _validDoc(sha256Hash: null);

      final result = await useCase.call(1);

      expect(result, isA<WordStagingBlocked>());
      expect(
        (result as WordStagingBlocked).error,
        WordStagingError.sourceHashNotAvailable,
      );
    });

    test('blocks when sha256 hash is empty', () async {
      repo.sourceRecord = _validDoc(sha256Hash: '');

      final result = await useCase.call(1);

      expect(result, isA<WordStagingBlocked>());
      expect(
        (result as WordStagingBlocked).error,
        WordStagingError.sourceHashNotAvailable,
      );
    });

    test('blocks when managed library root is null', () async {
      repo.managedLibraryRoot = null;

      final result = await useCase.call(1);

      expect(result, isA<WordStagingBlocked>());
      expect(
        (result as WordStagingBlocked).error,
        WordStagingError.noManagedLibraryRoot,
      );
    });

    test('blocks when managed library root is blank', () async {
      repo.managedLibraryRoot = '   ';

      final result = await useCase.call(1);

      expect(result, isA<WordStagingBlocked>());
      expect(
        (result as WordStagingBlocked).error,
        WordStagingError.noManagedLibraryRoot,
      );
    });

    test('blocks when staging directory cannot be created', () async {
      fs.ensureDirectoryFails = true;

      final result = await useCase.call(1);

      expect(result, isA<WordStagingBlocked>());
      expect(
        (result as WordStagingBlocked).error,
        WordStagingError.stagingDirectoryUnavailable,
      );
    });
  });

  group('StageWordSource – copy failures', () {
    test('returns WordStagingFailed when copy-to-temp fails', () async {
      fs.copyToTempFails = true;

      final result = await useCase.call(1);

      expect(result, isA<WordStagingFailed>());
      expect(
        (result as WordStagingFailed).error,
        WordStagingError.stagingCopyFailed,
      );
    });

    test('cleans up temp file when copy-to-temp fails', () async {
      fs.copyToTempFails = true;

      await useCase.call(1);

      expect(fs.deletedTempPaths, hasLength(1));
      expect(fs.deletedTempPaths.first, endsWith('.staging'));
    });

    test('returns WordStagingFailed when finalize fails', () async {
      fs.finalizeFails = true;

      final result = await useCase.call(1);

      expect(result, isA<WordStagingFailed>());
      expect(
        (result as WordStagingFailed).error,
        WordStagingError.stagingCopyFailed,
      );
    });

    test('cleans up temp file when finalize fails', () async {
      fs.finalizeFails = true;

      await useCase.call(1);

      expect(fs.deletedTempPaths, hasLength(1));
      expect(fs.deletedTempPaths.first, endsWith('.staging'));
    });

    test('no persistence when copy fails', () async {
      fs.copyToTempFails = true;
      repo.persistThrows = true; // Would also fail, but copy fails first.

      final result = await useCase.call(1);

      expect(result, isA<WordStagingFailed>());
      expect(
        (result as WordStagingFailed).error,
        WordStagingError.stagingCopyFailed,
      );
    });
  });

  group('StageWordSource – persistence failure', () {
    test('returns WordStagingFailed when persistence throws', () async {
      repo.persistThrows = true;

      final result = await useCase.call(1);

      expect(result, isA<WordStagingFailed>());
      expect(
        (result as WordStagingFailed).error,
        WordStagingError.persistenceFailed,
      );
    });
  });

  group('StageWordSource – safe message contract', () {
    test('all result types carry a non-empty safe message', () async {
      final scenarios = <Future<WordStagingResult>>[
        // Success
        () async {
          repo
            ..managedLibraryRoot = fakeRoot
            ..sourceRecord = _validDoc();
          return useCase.call(1);
        }(),
        // Already staged
        () async {
          repo.activeConversion = const WordConversionRecord(
            conversionId: 1,
            statusKey: 'pending_conversion',
          );
          return useCase.call(1);
        }(),
        // Blocked
        () async {
          repo.sourceRecord = null;
          return useCase.call(99);
        }(),
        // Failed
        () async {
          fs.copyToTempFails = true;
          return useCase.call(1);
        }(),
      ];

      for (final future in scenarios) {
        final result = await future;
        switch (result) {
          case WordStagingSuccess():
            break;
          case WordStagingAlreadyStaged():
            break;
          case WordStagingBlocked(:final safeMessage):
            expect(safeMessage, isNotEmpty);
          case WordStagingFailed(:final safeMessage):
            expect(safeMessage, isNotEmpty);
        }
      }
    });
  });

  group('StageWordSource – source file is never mutated', () {
    test(
      'temp deletion path is a staging path, never the original source',
      () async {
        // The fake tracks all deleteTempSafe calls. After a copy failure the
        // temp path (ending in .staging) must be cleaned up — never the source.
        const sourcePath = r'C:\sources\contract.doc';
        repo.sourceRecord = _validDoc(absolutePath: sourcePath);
        fs.copyToTempFails = true;

        await useCase.call(1);

        // The deleted temp path is a staging path (.staging suffix), not the source.
        for (final deleted in fs.deletedTempPaths) {
          expect(deleted, isNot(sourcePath));
          expect(deleted, endsWith('.staging'));
        }
      },
    );
  });
}
