// test/features/word_conversion/application/retry_word_conversion_test.dart

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_library_manager/features/word_conversion/application/retry_word_conversion.dart';
import 'package:legal_library_manager/features/word_conversion/domain/entities/conversion_retry_result.dart';
import 'package:legal_library_manager/features/word_conversion/domain/entities/word_conversion_execution_result.dart';
import 'package:legal_library_manager/features/word_conversion/domain/entities/word_conversion_execution_error.dart';
import 'package:legal_library_manager/features/word_conversion/domain/entities/word_staging_error.dart';
import 'package:legal_library_manager/features/word_conversion/domain/entities/word_staging_result.dart';

void main() {
  Future<WordStagingResult> unusedStage(int _) =>
      throw StateError('stage should not be called');

  group('RetryWordConversion', () {
    test(
      'pending conversion runs the existing conversion row directly',
      () async {
        final convertedIds = <int>[];
        final useCase = RetryWordConversion(
          stageWordSource: unusedStage,
          convertStagedWordSource: (id, {onStageChanged}) async {
            convertedIds.add(id);
            return WordConversionExecutionSuccess(
              outputFileId: 8,
              outputPath: r'C:\Library\WordOutput\a.pdf',
              pdfSha256: 'a' * 64,
            );
          },
        );

        final result = await useCase(
          conversionId: 7,
          sourceFileId: 99,
          statusKey: 'pending_conversion',
        );

        expect(result, isA<ConversionRetrySucceeded>());
        expect(convertedIds, [7]);
      },
    );

    test(
      'failed conversion restages source and converts the fresh row',
      () async {
        final stagedSourceIds = <int>[];
        final convertedIds = <int>[];
        final useCase = RetryWordConversion(
          stageWordSource: (sourceFileId) async {
            stagedSourceIds.add(sourceFileId);
            return const WordStagingSuccess(
              conversionId: 42,
              stagedPath: r'C:\Library\WordStaging\a.doc',
            );
          },
          convertStagedWordSource: (id, {onStageChanged}) async {
            convertedIds.add(id);
            return const WordConversionAlreadyCompleted(
              statusKey: 'needs_conversion_review',
            );
          },
        );

        final result = await useCase(
          conversionId: 7,
          sourceFileId: 99,
          statusKey: 'conversion_failed',
        );

        expect(result, isA<ConversionRetrySucceeded>());
        expect(stagedSourceIds, [99]);
        expect(convertedIds, [42]);
      },
    );

    test(
      'failed conversion reports blocked when restaging is blocked',
      () async {
        final useCase = RetryWordConversion(
          stageWordSource: (_) async => const WordStagingBlocked(
            error: WordStagingError.sourceFileNotWordDocument,
            safeMessage: 'invalid source',
          ),
          convertStagedWordSource: (_, {onStageChanged}) =>
              throw StateError('convert should not be called'),
        );

        final result = await useCase(
          conversionId: 7,
          sourceFileId: 99,
          statusKey: 'conversion_failed',
        );

        expect(result, isA<ConversionRetryBlocked>());
      },
    );

    test(
      'converting row is blocked instead of starting a duplicate run',
      () async {
        final useCase = RetryWordConversion(
          stageWordSource: unusedStage,
          convertStagedWordSource: (_, {onStageChanged}) =>
              throw StateError('convert should not be called'),
        );

        final result = await useCase(
          conversionId: 7,
          sourceFileId: 99,
          statusKey: 'converting',
        );

        expect(result, isA<ConversionRetryBlocked>());
      },
    );

    test('conversion execution failure maps to failed retry result', () async {
      final useCase = RetryWordConversion(
        stageWordSource: unusedStage,
        convertStagedWordSource: (_, {onStageChanged}) async =>
            const WordConversionExecutionFailed(
              error: WordConversionExecutionError.processFailed,
              safeMessage: 'conversion failed',
            ),
      );

      final result = await useCase(
        conversionId: 7,
        sourceFileId: 99,
        statusKey: 'pending_conversion',
      );

      expect(result, isA<ConversionRetryFailed>());
    });
  });
}
