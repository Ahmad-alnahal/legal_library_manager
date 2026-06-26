// test/features/word_conversion/application/convert_staged_word_source_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/import/domain/entities/import_error.dart';
import 'package:legal_library_manager/features/import/domain/entities/sha256_result.dart';
import 'package:legal_library_manager/features/import/domain/services/file_hasher.dart';
import 'package:legal_library_manager/features/word_conversion/application/convert_staged_word_source.dart';
import 'package:legal_library_manager/features/word_conversion/domain/entities/conversion_execution_record.dart';
import 'package:legal_library_manager/features/word_conversion/domain/entities/conversion_stage.dart';
import 'package:legal_library_manager/features/word_conversion/domain/entities/conversion_review_item.dart';
import 'package:legal_library_manager/features/word_conversion/domain/entities/conversion_work_item.dart';
import 'package:legal_library_manager/features/word_conversion/domain/entities/word_conversion_execution_error.dart';
import 'package:legal_library_manager/features/word_conversion/domain/entities/word_conversion_execution_result.dart';
import 'package:legal_library_manager/features/word_conversion/domain/entities/word_conversion_record.dart';
import 'package:legal_library_manager/features/word_conversion/domain/entities/word_source_record.dart';
import 'package:legal_library_manager/features/word_conversion/domain/repositories/word_conversion_repository.dart';
import 'package:legal_library_manager/features/word_conversion/domain/services/microsoft_word_probe.dart';
import 'package:legal_library_manager/features/word_conversion/domain/services/word_converter.dart';
import 'package:legal_library_manager/features/word_conversion/domain/services/word_output_filesystem.dart';
import 'package:legal_library_manager/features/word_conversion/domain/services/word_staging_filesystem.dart';

// ── Test doubles ─────────────────────────────────────────────────────────────

class _FakeRepository implements WordConversionRepository {
  ConversionExecutionRecord? conversionRecord;
  WordSourceRecord? sourceRecord;
  String? managedLibraryRoot;
  bool markConvertingReturn = true;
  bool finalizeThrows = false;
  bool recordFailedThrows = false;
  int finalizeReturn = 99;
  // tracking
  String? lastErrorCode;
  bool markConvertingCalled = false;
  bool finalizeCalled = false;
  bool recordFailedCalled = false;
  bool allocateCalled = false;

  @override
  Future<ConversionExecutionRecord?> loadConversionForExecution(
    int conversionId,
  ) async => conversionRecord;

  @override
  Future<WordSourceRecord?> loadSourceRecord(int fileId) async => sourceRecord;

  @override
  Future<String?> loadManagedLibraryRoot() async => managedLibraryRoot;

  @override
  Future<bool> markConverting(int conversionId, String nowIso) async {
    markConvertingCalled = true;
    return markConvertingReturn;
  }

  @override
  Future<String> allocateDocumentCode(int documentId) async {
    allocateCalled = true;
    return 'DOC-0000001';
  }

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
  }) async {
    finalizeCalled = true;
    if (finalizeThrows) throw Exception('db error');
    return finalizeReturn;
  }

  @override
  Future<void> recordFailedConversion({
    required int conversionId,
    required int documentId,
    required int sourceFileId,
    required String errorCode,
    required String errorMessageSafe,
    required String operationId,
    required String nowIso,
  }) async {
    recordFailedCalled = true;
    lastErrorCode = errorCode;
    if (recordFailedThrows) throw Exception('db error');
  }

  // ── Unused P1.2 methods ────────────────────────────────────────────────────
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

  // ── Unused P1.4 review methods ─────────────────────────────────────────────
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
}

class _FakeProbe implements MicrosoftWordProbe {
  bool found = true;
  String executablePath = 'powershell.exe';

  @override
  Future<MicrosoftWordProbeResult> probe() async {
    if (found) return MicrosoftWordFound(executablePath: executablePath);
    return const MicrosoftWordNotFound();
  }
}

/// Converter that echoes back `outputPath` as the generated PDF path,
/// simulating Microsoft Word writing to the exact path it was given.
class _FakeConverter implements WordConverter {
  WordConverterResult? _overrideResult;
  String? lastStagedPath;
  String? lastOutputPath;

  void setFailed(WordConverterError e, String msg) {
    _overrideResult = WordConverterFailed(error: e, safeMessage: msg);
  }

  void clearOverride() => _overrideResult = null;

  @override
  Future<WordConverterResult> convert({
    required String executablePath,
    required String stagedPath,
    required String outputPath,
    void Function(ConversionStage stage)? onStageChanged,
  }) async {
    lastStagedPath = stagedPath;
    lastOutputPath = outputPath;
    if (_overrideResult != null) return _overrideResult!;
    // Simulate Word writing the file: record the path it was told to use.
    return WordConverterOutput(generatedPdfPath: outputPath);
  }
}

/// Output filesystem fake that stores existence/size/header by path.
/// Defaults to "file exists, size=1024, PDF header" for any path not
/// explicitly configured, so happy-path tests need minimal setup.
class _FakeOutputFs implements WordOutputFilesystem {
  bool ensureDirectoryFails = false;
  bool renameFails = false;

  // Optional per-path overrides; if absent, defaults are used.
  final Set<String> _nonExistentPaths = {};
  Map<String, int>? _fileSizes;
  Map<String, List<int>>? _headerBytes;

  List<String> deletedFiles = [];

  void markNonExistent(String path) => _nonExistentPaths.add(path);
  void setFileSize(String path, int size) => (_fileSizes ??= {})[path] = size;
  void setHeaderBytes(String path, List<int> bytes) =>
      (_headerBytes ??= {})[path] = bytes;

  @override
  Future<OutputOperationResult> ensureOutputDirectory(String outputDir) async {
    if (ensureDirectoryFails) {
      return const OutputFailure(safeMessage: 'test dir failure');
    }
    return const OutputSuccess();
  }

  @override
  bool isExistingFile(String path) => !_nonExistentPaths.contains(path);

  @override
  Future<int?> fileSize(String path) async =>
      _fileSizes != null ? (_fileSizes![path] ?? 1024) : 1024;

  @override
  Future<List<int>?> readFirstBytes(String path, int count) async =>
      _headerBytes != null ? (_headerBytes![path] ?? _kPdfHeader) : _kPdfHeader;

  @override
  Future<OutputOperationResult> renameOutputFile(
    String fromPath,
    String toPath,
  ) async {
    if (renameFails) {
      return const OutputFailure(safeMessage: 'test rename failure');
    }
    return const OutputSuccess();
  }

  @override
  Future<OutputOperationResult> deleteOutputFileSafe(
    String path,
    String outputDir,
  ) async {
    deletedFiles.add(path);
    return const OutputSuccess();
  }
}

class _FakeStagingFs implements WordStagingFilesystem {
  bool stagedFileExists = true;
  List<String> deletedStagedPaths = [];

  @override
  bool isExistingFile(String path) => stagedFileExists;

  @override
  Future<StagingOperationResult> deleteStagedFileSafe(
    String path,
    String stagingDir,
  ) async {
    deletedStagedPaths.add(path);
    return const StagingSuccess();
  }

  // Unused by ConvertStagedWordSource — stubs satisfy the interface.
  @override
  Future<StagingOperationResult> ensureStagingDirectory(String stagingDir) =>
      throw UnimplementedError();
  @override
  Future<StagingOperationResult> copyToTemp(
    String sourcePath,
    String tempDestPath,
  ) => throw UnimplementedError();
  @override
  Future<StagingOperationResult> finalize(String tempPath, String finalPath) =>
      throw UnimplementedError();
  @override
  Future<StagingOperationResult> deleteTempSafe(
    String tempPath,
    String stagingDir,
  ) => throw UnimplementedError();
}

// Valid 64-char lowercase hex SHA-256 for tests.
const _kPdfHash =
    'deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef';
const _kPdfHeader = <int>[0x25, 0x50, 0x44, 0x46]; // %PDF

class _FakeHasher implements FileHasher {
  Sha256Result result = Sha256Result.success(_kPdfHash);

  @override
  Future<Sha256Result> hashFile(
    String absolutePath, {
    HashCancellation? cancellation,
    void Function(HashProgress progress)? onProgress,
  }) async => result;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

ConversionExecutionRecord _pendingRecord({
  int conversionId = 1,
  int documentId = 10,
  int sourceFileId = 2,
}) => ConversionExecutionRecord(
  conversionId: conversionId,
  documentId: documentId,
  sourceFileId: sourceFileId,
  statusKey: 'pending_conversion',
);

WordSourceRecord _docSourceRecord({
  int fileId = 2,
  int documentId = 10,
  String sha256Hash = 'abc123',
}) => WordSourceRecord(
  fileId: fileId,
  documentId: documentId,
  absolutePath: r'C:\sources\contract.doc',
  extension: '.doc',
  sha256Hash: sha256Hash,
  fileHealthKey: 'healthy',
  fileRoleKey: 'source_original',
);

const _root = r'C:\Library';
const _stagedPath = r'C:\Library\WordStaging\abc123.doc';

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late _FakeRepository repo;
  late _FakeProbe probe;
  late _FakeConverter converter;
  late _FakeOutputFs outputFs;
  late _FakeStagingFs stagingFs;
  late _FakeHasher hasher;
  late ConvertStagedWordSource useCase;

  setUp(() {
    repo = _FakeRepository()
      ..conversionRecord = _pendingRecord()
      ..sourceRecord = _docSourceRecord()
      ..managedLibraryRoot = _root;

    probe = _FakeProbe();
    converter = _FakeConverter();
    outputFs = _FakeOutputFs();
    stagingFs = _FakeStagingFs();
    hasher = _FakeHasher();

    useCase = ConvertStagedWordSource(
      repository: repo,
      probe: probe,
      converter: converter,
      outputFs: outputFs,
      stagingFs: stagingFs,
      hasher: hasher,
    );
  });

  // ── Happy path ─────────────────────────────────────────────────────────────

  group('ConvertStagedWordSource – happy path', () {
    test(
      'returns WordConversionExecutionSuccess with correct fields',
      () async {
        repo.finalizeReturn = 77;

        final result = await useCase.call(1);

        expect(result, isA<WordConversionExecutionSuccess>());
        final success = result as WordConversionExecutionSuccess;
        expect(success.outputFileId, 77);
        expect(success.pdfSha256, _kPdfHash);
        // Output goes to WordStaging/ as a content-addressed <sha256>.pdf file.
        expect(success.outputPath, contains(r'\WordStaging\'));
        expect(success.outputPath, endsWith('$_kPdfHash.pdf'));
      },
    );

    test(
      'marks conversion as converting before running the converter',
      () async {
        await useCase.call(1);

        expect(repo.markConvertingCalled, isTrue);
      },
    );

    test('calls finalizeSuccessfulConversion on success', () async {
      await useCase.call(1);

      expect(repo.finalizeCalled, isTrue);
    });

    test('does not call recordFailedConversion on success', () async {
      await useCase.call(1);

      expect(repo.recordFailedCalled, isFalse);
    });

    test(
      'does NOT allocate document code during conversion (deferred to managed-copy)',
      () async {
        await useCase.call(1);

        expect(repo.allocateCalled, isFalse);
      },
    );

    test(
      'final output path is <sha256>.pdf inside WordStaging, not files/',
      () async {
        final result = await useCase.call(1);

        final success = result as WordConversionExecutionSuccess;
        expect(success.outputPath, contains(r'\WordStaging\'));
        expect(success.outputPath, isNot(contains(r'\files\')));
        expect(success.outputPath, isNot(contains('DOC-')));
        expect(success.outputPath, endsWith('$_kPdfHash.pdf'));
      },
    );

    test('staged .doc copy is deleted after successful conversion', () async {
      await useCase.call(1);

      expect(stagingFs.deletedStagedPaths, contains(_stagedPath));
    });
  });

  // ── Already-completed idempotency ──────────────────────────────────────────

  group('ConvertStagedWordSource – already completed', () {
    for (final status in [
      'needs_conversion_review',
      'conversion_approved',
      'conversion_succeeded',
    ]) {
      test(
        'returns WordConversionAlreadyCompleted for status=$status',
        () async {
          repo.conversionRecord = ConversionExecutionRecord(
            conversionId: 1,
            documentId: 10,
            sourceFileId: 2,
            statusKey: status,
          );

          final result = await useCase.call(1);

          expect(result, isA<WordConversionAlreadyCompleted>());
          expect((result as WordConversionAlreadyCompleted).statusKey, status);
        },
      );
    }
  });

  // ── Pre-flight blocks (do not touch DB) ────────────────────────────────────

  group('ConvertStagedWordSource – pre-flight blocks', () {
    test('blocks when conversion record does not exist', () async {
      repo.conversionRecord = null;

      final result = await useCase.call(99);

      expect(result, isA<WordConversionExecutionBlocked>());
      expect(
        (result as WordConversionExecutionBlocked).error,
        WordConversionExecutionError.conversionNotFound,
      );
      expect(repo.markConvertingCalled, isFalse);
    });

    test('blocks when status is converting', () async {
      repo.conversionRecord = ConversionExecutionRecord(
        conversionId: 1,
        documentId: 10,
        sourceFileId: 2,
        statusKey: 'converting',
      );

      final result = await useCase.call(1);

      expect(result, isA<WordConversionExecutionBlocked>());
      expect(
        (result as WordConversionExecutionBlocked).error,
        WordConversionExecutionError.conversionAlreadyInProgress,
      );
      expect(repo.markConvertingCalled, isFalse);
    });

    test('blocks when status is conversion_failed', () async {
      repo.conversionRecord = ConversionExecutionRecord(
        conversionId: 1,
        documentId: 10,
        sourceFileId: 2,
        statusKey: 'conversion_failed',
      );

      final result = await useCase.call(1);

      expect(result, isA<WordConversionExecutionBlocked>());
      expect(repo.markConvertingCalled, isFalse);
    });

    test('blocks when source record is not found', () async {
      repo.sourceRecord = null;

      final result = await useCase.call(1);

      expect(result, isA<WordConversionExecutionBlocked>());
      expect(
        (result as WordConversionExecutionBlocked).error,
        WordConversionExecutionError.sourceNotFound,
      );
      expect(repo.markConvertingCalled, isFalse);
    });

    test('blocks when managed library root is null', () async {
      repo.managedLibraryRoot = null;

      final result = await useCase.call(1);

      expect(result, isA<WordConversionExecutionBlocked>());
      expect(
        (result as WordConversionExecutionBlocked).error,
        WordConversionExecutionError.libraryRootNotConfigured,
      );
      expect(repo.markConvertingCalled, isFalse);
    });

    test('blocks when source sha256 hash is null/empty', () async {
      repo.sourceRecord = _docSourceRecord(sha256Hash: '');

      final result = await useCase.call(1);

      expect(result, isA<WordConversionExecutionBlocked>());
      expect(
        (result as WordConversionExecutionBlocked).error,
        WordConversionExecutionError.stagedFileNotFound,
      );
      expect(repo.markConvertingCalled, isFalse);
    });

    test('blocks when staged file is missing from disk', () async {
      stagingFs.stagedFileExists = false;

      final result = await useCase.call(1);

      expect(result, isA<WordConversionExecutionBlocked>());
      expect(
        (result as WordConversionExecutionBlocked).error,
        WordConversionExecutionError.stagedFileNotFound,
      );
      expect(repo.markConvertingCalled, isFalse);
    });

    test('blocks when Microsoft Word is not found', () async {
      probe.found = false;

      final result = await useCase.call(1);

      expect(result, isA<WordConversionExecutionBlocked>());
      expect(
        (result as WordConversionExecutionBlocked).error,
        WordConversionExecutionError.microsoftWordUnavailable,
      );
      expect(repo.markConvertingCalled, isFalse);
    });

    test('blocks when output directory cannot be created', () async {
      outputFs.ensureDirectoryFails = true;

      final result = await useCase.call(1);

      expect(result, isA<WordConversionExecutionBlocked>());
      expect(
        (result as WordConversionExecutionBlocked).error,
        WordConversionExecutionError.outputDirectoryUnavailable,
      );
      expect(repo.markConvertingCalled, isFalse);
    });

    test('blocks when markConverting returns false (race condition)', () async {
      repo.markConvertingReturn = false;

      final result = await useCase.call(1);

      expect(result, isA<WordConversionExecutionBlocked>());
      expect(
        (result as WordConversionExecutionBlocked).error,
        WordConversionExecutionError.conversionAlreadyInProgress,
      );
    });
  });

  // ── Post-markConverting failures (DB updated to conversion_failed) ──────────

  group('ConvertStagedWordSource – conversion failures', () {
    test(
      'returns WordConversionExecutionFailed when Microsoft Word export fails',
      () async {
        converter.setFailed(
          WordConverterError.conversionFailed,
          'Microsoft Word error',
        );

        final result = await useCase.call(1);

        expect(result, isA<WordConversionExecutionFailed>());
        expect(
          (result as WordConversionExecutionFailed).error,
          WordConversionExecutionError.processFailed,
        );
        expect(repo.recordFailedCalled, isTrue);
      },
    );

    test('cleans up temp .converting file when Word export fails', () async {
      converter.setFailed(
        WordConverterError.conversionFailed,
        'Microsoft Word error',
      );

      await useCase.call(1);

      // Temp file cleanup: deleted file must be in WordStaging/, not files/.
      final inStaging = outputFs.deletedFiles.any(
        (p) => p.contains(r'\WordStaging\'),
      );
      expect(inStaging, isTrue);
      final inFiles = outputFs.deletedFiles.any((p) => p.contains(r'\files\'));
      expect(inFiles, isFalse);
    });

    test(
      'returns WordConversionExecutionFailed when output file not created',
      () async {
        // Use _NonExistentOutputFs so isExistingFile always returns false
        // for the converter output path.
        final uc2 = ConvertStagedWordSource(
          repository: repo,
          probe: probe,
          converter: _FakeConverter(),
          outputFs: _NonExistentOutputFs(),
          stagingFs: stagingFs,
          hasher: hasher,
        );

        final result = await uc2.call(1);

        expect(result, isA<WordConversionExecutionFailed>());
        expect(
          (result as WordConversionExecutionFailed).error,
          WordConversionExecutionError.outputNotCreated,
        );
        expect(repo.recordFailedCalled, isTrue);
      },
    );

    test(
      'returns WordConversionExecutionFailed when output file is empty',
      () async {
        // Override fileSize to return 0 for any path.
        final emptyFs = _FakeOutputFs();
        emptyFs.setFileSize('__any__', 0);
        final uc = ConvertStagedWordSource(
          repository: repo,
          probe: probe,
          converter: converter,
          outputFs: _ZeroSizeOutputFs(),
          stagingFs: stagingFs,
          hasher: hasher,
        );

        final result = await uc.call(1);

        expect(result, isA<WordConversionExecutionFailed>());
        expect(
          (result as WordConversionExecutionFailed).error,
          WordConversionExecutionError.outputEmpty,
        );
        expect(repo.recordFailedCalled, isTrue);
      },
    );

    test(
      'returns WordConversionExecutionFailed when PDF header is invalid',
      () async {
        final uc = ConvertStagedWordSource(
          repository: repo,
          probe: probe,
          converter: converter,
          outputFs: _BadHeaderOutputFs(),
          stagingFs: stagingFs,
          hasher: hasher,
        );

        final result = await uc.call(1);

        expect(result, isA<WordConversionExecutionFailed>());
        expect(
          (result as WordConversionExecutionFailed).error,
          WordConversionExecutionError.outputNotPdf,
        );
        expect(repo.recordFailedCalled, isTrue);
      },
    );

    test('returns WordConversionExecutionFailed when hashing fails', () async {
      hasher.result = Sha256Result.failure(
        const ImportError(code: ImportErrorCode.hashFailed),
      );

      final result = await useCase.call(1);

      expect(result, isA<WordConversionExecutionFailed>());
      expect(
        (result as WordConversionExecutionFailed).error,
        WordConversionExecutionError.hashFailed,
      );
      expect(repo.recordFailedCalled, isTrue);
    });

    test(
      'returns WordConversionExecutionFailed when persistence fails',
      () async {
        repo.finalizeThrows = true;

        final result = await useCase.call(1);

        expect(result, isA<WordConversionExecutionFailed>());
        expect(
          (result as WordConversionExecutionFailed).error,
          WordConversionExecutionError.persistenceFailed,
        );
      },
    );

    test(
      'still returns failure result when recordFailedConversion throws',
      () async {
        converter.setFailed(
          WordConverterError.conversionFailed,
          'Microsoft Word error',
        );
        repo.recordFailedThrows = true;

        final result = await useCase.call(1);

        expect(result, isA<WordConversionExecutionFailed>());
      },
    );
  });

  // ── Source file safety invariant ────────────────────────────────────────────

  group('ConvertStagedWordSource – source file safety', () {
    test('the original source path is never passed to the converter', () async {
      const originalSourcePath = r'C:\sources\contract.doc';

      await useCase.call(1);

      expect(converter.lastStagedPath, isNot(originalSourcePath));
    });

    test(
      'the staged path (not original source) is passed to the converter',
      () async {
        await useCase.call(1);

        expect(converter.lastStagedPath, contains('WordStaging'));
        expect(converter.lastStagedPath, contains('abc123'));
      },
    );

    test(
      'deleted files on failure are inside WordStaging/, not files/',
      () async {
        final uc = ConvertStagedWordSource(
          repository: repo,
          probe: probe,
          converter: converter,
          outputFs: _BadHeaderOutputFs(),
          stagingFs: stagingFs,
          hasher: hasher,
        );

        await uc.call(1);

        for (final deleted in (_BadHeaderOutputFs._lastDeleted)) {
          expect(deleted, contains('WordStaging'));
          expect(deleted, isNot(contains(r'\files\')));
          expect(deleted, isNot(r'C:\sources\contract.doc'));
        }
      },
    );

    test(
      'converter receives temp path inside WordStaging/, not files/ or WordOutput/',
      () async {
        await useCase.call(1);

        expect(converter.lastOutputPath, contains(r'\WordStaging\'));
        expect(converter.lastOutputPath, isNot(contains(r'\files\')));
        expect(converter.lastOutputPath, isNot(contains('WordOutput')));
      },
    );
  });

  // ── Safe message contract ───────────────────────────────────────────────────

  group('ConvertStagedWordSource – safe messages', () {
    test(
      'all blocked and failed results carry non-empty safe messages',
      () async {
        final scenarios = <Future<WordConversionExecutionResult>>[
          () async {
            repo.conversionRecord = null;
            return useCase.call(99);
          }(),
          () async {
            repo.sourceRecord = null;
            return useCase.call(1);
          }(),
          () async {
            repo.managedLibraryRoot = null;
            return useCase.call(1);
          }(),
          () async {
            probe.found = false;
            return useCase.call(1);
          }(),
          () async {
            converter.setFailed(
              WordConverterError.processLaunchFailed,
              'launch failure',
            );
            return useCase.call(1);
          }(),
        ];

        for (final future in scenarios) {
          final result = await future;
          switch (result) {
            case WordConversionExecutionSuccess():
              break;
            case WordConversionAlreadyCompleted():
              break;
            case WordConversionExecutionBlocked(:final safeMessage):
              expect(safeMessage, isNotEmpty);
            case WordConversionExecutionFailed(:final safeMessage):
              expect(safeMessage, isNotEmpty);
          }
          // Reset between iterations.
          repo.conversionRecord = _pendingRecord();
          repo.sourceRecord = _docSourceRecord();
          repo.managedLibraryRoot = _root;
          repo.markConvertingReturn = true;
          repo.recordFailedCalled = false;
          probe.found = true;
          converter.clearOverride();
          hasher.result = Sha256Result.success(_kPdfHash);
          stagingFs.stagedFileExists = true;
          stagingFs.deletedStagedPaths = [];
        }
      },
    );
  });

  group('ConvertStagedWordSource – stage reporting', () {
    test('emits preparing before calling converter', () async {
      final stages = <ConversionStage>[];
      await useCase.call(1, onStageChanged: stages.add);
      expect(stages, contains(ConversionStage.preparing));
      final prepIdx = stages.indexOf(ConversionStage.preparing);
      final openIdx = stages.indexOf(ConversionStage.openingDocument);
      if (openIdx >= 0) expect(prepIdx, lessThan(openIdx));
    });

    test('emits validatingOutput after converter succeeds', () async {
      final stages = <ConversionStage>[];
      await useCase.call(1, onStageChanged: stages.add);
      expect(stages, contains(ConversionStage.validatingOutput));
    });

    test('emits savingResult before persisting', () async {
      final stages = <ConversionStage>[];
      await useCase.call(1, onStageChanged: stages.add);
      expect(stages, contains(ConversionStage.savingResult));
    });

    test('emits cleaningUp after successful persist', () async {
      final stages = <ConversionStage>[];
      await useCase.call(1, onStageChanged: stages.add);
      expect(stages, contains(ConversionStage.cleaningUp));
      final saveIdx = stages.indexOf(ConversionStage.savingResult);
      final cleanIdx = stages.indexOf(ConversionStage.cleaningUp);
      if (saveIdx >= 0) expect(cleanIdx, greaterThan(saveIdx));
    });

    test('stage callback receives null onStageChanged without error', () async {
      final result = await useCase.call(1);
      expect(result, isA<WordConversionExecutionSuccess>());
    });
  });
}

// ── Specialized output-fs helpers for failure scenarios ─────────────────────

/// OutputFilesystem that reports every file as non-existent.
class _NonExistentOutputFs extends _FakeOutputFs {
  @override
  bool isExistingFile(String path) => false;
}

/// OutputFilesystem that reports every file as zero-size.
class _ZeroSizeOutputFs extends _FakeOutputFs {
  @override
  Future<int?> fileSize(String path) async => 0;
}

/// OutputFilesystem that returns a bad (non-PDF) header for every file.
class _BadHeaderOutputFs extends _FakeOutputFs {
  static final List<String> _lastDeleted = [];

  @override
  Future<List<int>?> readFirstBytes(String path, int count) async => [
    0x00,
    0x00,
    0x00,
    0x00,
  ];

  @override
  Future<OutputOperationResult> deleteOutputFileSafe(
    String path,
    String outputDir,
  ) async {
    _lastDeleted
      ..clear()
      ..add(path);
    return const OutputSuccess();
  }
}
