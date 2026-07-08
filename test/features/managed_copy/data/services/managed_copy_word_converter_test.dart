// test/features/managed_copy/data/services/managed_copy_word_converter_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/import/domain/entities/import_error.dart';
import 'package:legal_library_manager/features/import/domain/entities/sha256_result.dart';
import 'package:legal_library_manager/features/import/domain/services/file_hasher.dart';
import 'package:legal_library_manager/features/managed_copy/data/services/managed_copy_word_converter.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/local_file_availability_checker.dart';
import 'package:legal_library_manager/features/managed_copy/domain/services/word_document_converter.dart';
import 'package:legal_library_manager/features/word_conversion/data/services/windows_word_output_filesystem.dart';
import 'package:legal_library_manager/features/word_conversion/domain/entities/conversion_stage.dart';
import 'package:legal_library_manager/features/word_conversion/domain/services/microsoft_word_probe.dart';
import 'package:legal_library_manager/features/word_conversion/domain/services/word_converter.dart';

// ─── Fakes ───────────────────────────────────────────────────────────────────

class _FakeProbe implements MicrosoftWordProbe {
  MicrosoftWordProbeResult result = const MicrosoftWordFound(
    executablePath: 'powershell.exe',
  );

  @override
  Future<MicrosoftWordProbeResult> probe() async => result;
}

class _FakeChecker implements LocalFileAvailabilityChecker {
  bool available = true;
  final List<String> checkedPaths = [];

  @override
  bool isLocallyAvailable(String absolutePath) {
    checkedPaths.add(absolutePath);
    return available;
  }
}

class _FakeHasher implements FileHasher {
  String? hash =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  @override
  Future<Sha256Result> hashFile(
    String absolutePath, {
    HashCancellation? cancellation,
    void Function(HashProgress progress)? onProgress,
  }) async {
    if (hash == null) {
      return Sha256Result.failure(
        ImportError(
          code: ImportErrorCode.hashFailed,
          path: absolutePath,
          message: 'simulated hash failure',
        ),
      );
    }
    return Sha256Result.success(hash!);
  }
}

/// Fake [WordConverter] that also inspects, from inside [convert], whether
/// the staged path it was handed still carries a Zone.Identifier ADS —
/// this must be observed synchronously before [ManagedCopyWordConverter]
/// deletes the staged temp copy.
class _CapturingConverter implements WordConverter {
  WordConverterResult convertResult = const WordConverterFailed(
    error: WordConverterError.conversionFailed,
    safeMessage: 'not configured',
  );
  WordConverterResult blankResult = const WordConverterFailed(
    error: WordConverterError.conversionFailed,
    safeMessage: 'not configured',
  );

  final List<String> convertStagedPaths = [];
  int convertCalls = 0;
  int convertBlankDocumentCalls = 0;
  bool? stagedHasZoneIdentifier;

  @override
  Future<WordConverterResult> convert({
    required String executablePath,
    required String stagedPath,
    required String outputPath,
    void Function(ConversionStage stage)? onStageChanged,
  }) async {
    convertCalls++;
    convertStagedPaths.add(stagedPath);
    stagedHasZoneIdentifier = File('$stagedPath:Zone.Identifier').existsSync();
    if (convertResult is WordConverterOutput) {
      final out = convertResult as WordConverterOutput;
      await File(out.generatedPdfPath).writeAsBytes(_validPdfBytes);
    }
    return convertResult;
  }

  final List<String> convertBlankDocumentOutputPaths = [];

  @override
  Future<WordConverterResult> convertBlankDocument({
    required String executablePath,
    required String outputPath,
  }) async {
    convertBlankDocumentCalls++;
    convertBlankDocumentOutputPaths.add(outputPath);
    // The real implementation writes to the exact outputPath it was given
    // (computed by the caller) — not to a path of its own choosing.
    if (blankResult is WordConverterOutput) {
      await File(outputPath).writeAsBytes(_validPdfBytes);
    }
    return blankResult;
  }
}

const _validPdfBytes = [0x25, 0x50, 0x44, 0x46, 0x2d, 0x31, 0x2e, 0x34];

// ─── Tests ───────────────────────────────────────────────────────────────────

void main() {
  late Directory tempOutputDir;
  late Directory sourceDir;
  late String sourceDocPath;
  late _FakeProbe probe;
  late _FakeChecker checker;
  late _FakeHasher hasher;
  late _CapturingConverter converter;
  late ManagedCopyWordConverter sut;

  setUp(() async {
    tempOutputDir = await Directory.systemTemp.createTemp('marjiy_word_out_');
    sourceDir = await Directory.systemTemp.createTemp('marjiy_word_src_');
    sourceDocPath = '${sourceDir.path}\\report.doc';
    await File(sourceDocPath).writeAsString('fake .doc content');

    probe = _FakeProbe();
    checker = _FakeChecker();
    hasher = _FakeHasher();
    converter = _CapturingConverter()
      ..convertResult = WordConverterOutput(
        generatedPdfPath: '${tempOutputDir.path}\\op1.word_out',
      );

    sut = ManagedCopyWordConverter(
      probe: probe,
      converter: converter,
      outputFs: const WindowsWordOutputFilesystem(),
      hasher: hasher,
      localFileChecker: checker,
    );
  });

  tearDown(() async {
    if (tempOutputDir.existsSync()) await tempOutputDir.delete(recursive: true);
    if (sourceDir.existsSync()) await sourceDir.delete(recursive: true);
  });

  group('Microsoft Word not found', () {
    test(
      'returns microsoft_word_unavailable without touching the source',
      () async {
        probe.result = const MicrosoftWordNotFound();

        final result = await sut.convert(
          sourceDocPath: sourceDocPath,
          tempOutputDir: tempOutputDir.path,
          operationId: 'op1',
        );

        expect(result, isA<WordDocumentConversionFailed>());
        expect(
          (result as WordDocumentConversionFailed).errorCode,
          'microsoft_word_unavailable',
        );
        expect(checker.checkedPaths, isEmpty);
        expect(converter.convertCalls, 0);
        expect(converter.convertBlankDocumentCalls, 0);
      },
    );
  });

  group('source not locally available (OneDrive placeholder — Task D)', () {
    test(
      'returns source_not_available_offline and never stages a temp copy',
      () async {
        checker.available = false;

        final result = await sut.convert(
          sourceDocPath: sourceDocPath,
          tempOutputDir: tempOutputDir.path,
          operationId: 'op1',
        );

        expect(result, isA<WordDocumentConversionFailed>());
        expect(
          (result as WordDocumentConversionFailed).errorCode,
          'source_not_available_offline',
        );
        expect(checker.checkedPaths, [sourceDocPath]);
        expect(converter.convertCalls, 0);
        expect(
          tempOutputDir.listSync().where((f) => f.path.endsWith('.doc')),
          isEmpty,
          reason: 'no temp .doc copy must be created for an offline source',
        );
      },
    );

    test(
      'checks availability before creating the temp output directory contents',
      () async {
        checker.available = false;
        await sut.convert(
          sourceDocPath: sourceDocPath,
          tempOutputDir: tempOutputDir.path,
          operationId: 'op1',
        );
        expect(tempOutputDir.listSync(), isEmpty);
      },
    );
  });

  group('Zone.Identifier stripping', () {
    test('removes the staged copy Zone.Identifier before handing it to the '
        'converter', () async {
      await File(
        '$sourceDocPath:Zone.Identifier',
      ).writeAsString('[ZoneTransfer]\r\nZoneId=3\r\n');

      await sut.convert(
        sourceDocPath: sourceDocPath,
        tempOutputDir: tempOutputDir.path,
        operationId: 'op1',
      );

      expect(converter.stagedHasZoneIdentifier, isFalse);
    });

    test(
      'conversion still proceeds when the source has no Zone.Identifier',
      () async {
        final result = await sut.convert(
          sourceDocPath: sourceDocPath,
          tempOutputDir: tempOutputDir.path,
          operationId: 'op1',
        );
        expect(result, isA<WordDocumentConversionSuccess>());
      },
    );
  });

  group('offline capability diagnostic (Task B)', () {
    test('returns local_word_unavailable_offline_or_not_activated when both '
        'the real conversion and the blank-document probe fail', () async {
      converter
        ..convertResult = const WordConverterFailed(
          error: WordConverterError.conversionFailed,
          safeMessage: 'document-specific failure',
        )
        ..blankResult = const WordConverterFailed(
          error: WordConverterError.conversionFailed,
          safeMessage: 'blank export also failed',
        );

      final result = await sut.convert(
        sourceDocPath: sourceDocPath,
        tempOutputDir: tempOutputDir.path,
        operationId: 'op1',
      );

      expect(result, isA<WordDocumentConversionFailed>());
      expect(
        (result as WordDocumentConversionFailed).errorCode,
        'local_word_unavailable_offline_or_not_activated',
      );
      expect(converter.convertBlankDocumentCalls, 1);
    });

    test('returns word_process_failed (document-specific) when the blank-'
        'document probe succeeds, proving Word itself is capable', () async {
      converter
        ..convertResult = const WordConverterFailed(
          error: WordConverterError.conversionFailed,
          safeMessage: 'this document could not be opened',
        )
        ..blankResult = const WordConverterOutput(generatedPdfPath: 'unused');

      final result = await sut.convert(
        sourceDocPath: sourceDocPath,
        tempOutputDir: tempOutputDir.path,
        operationId: 'op1',
      );

      expect(result, isA<WordDocumentConversionFailed>());
      expect(
        (result as WordDocumentConversionFailed).errorCode,
        'word_process_failed',
      );
      expect(converter.convertBlankDocumentCalls, 1);
    });

    test(
      'never runs the capability probe on a successful conversion',
      () async {
        final result = await sut.convert(
          sourceDocPath: sourceDocPath,
          tempOutputDir: tempOutputDir.path,
          operationId: 'op1',
        );
        expect(result, isA<WordDocumentConversionSuccess>());
        expect(converter.convertBlankDocumentCalls, 0);
      },
    );

    test(
      'cleans up the capability probe output regardless of outcome',
      () async {
        converter
          ..convertResult = const WordConverterFailed(
            error: WordConverterError.conversionFailed,
            safeMessage: 'document-specific failure',
          )
          ..blankResult = const WordConverterOutput(generatedPdfPath: 'unused');

        await sut.convert(
          sourceDocPath: sourceDocPath,
          tempOutputDir: tempOutputDir.path,
          operationId: 'op1',
        );

        expect(converter.convertBlankDocumentOutputPaths, hasLength(1));
        final probePath = converter.convertBlankDocumentOutputPaths.single;
        expect(File(probePath).existsSync(), isFalse);
      },
    );
  });

  group('happy path', () {
    test('returns a verified success with hash and size', () async {
      final result = await sut.convert(
        sourceDocPath: sourceDocPath,
        tempOutputDir: tempOutputDir.path,
        operationId: 'op1',
      );

      expect(result, isA<WordDocumentConversionSuccess>());
      final success = result as WordDocumentConversionSuccess;
      expect(success.pdfSha256, hasher.hash);
      expect(success.fileSizeBytes, _validPdfBytes.length);
      expect(File(success.tempPdfPath).existsSync(), isTrue);
    });

    test('temp .doc copy is deleted after conversion', () async {
      await sut.convert(
        sourceDocPath: sourceDocPath,
        tempOutputDir: tempOutputDir.path,
        operationId: 'op1',
      );
      expect(
        tempOutputDir.listSync().where((f) => f.path.endsWith('.doc')),
        isEmpty,
      );
    });

    test('original source file is never modified or deleted', () async {
      await sut.convert(
        sourceDocPath: sourceDocPath,
        tempOutputDir: tempOutputDir.path,
        operationId: 'op1',
      );
      expect(File(sourceDocPath).existsSync(), isTrue);
      expect(await File(sourceDocPath).readAsString(), 'fake .doc content');
    });
  });
}
