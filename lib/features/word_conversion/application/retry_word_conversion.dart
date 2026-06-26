// lib/features/word_conversion/application/retry_word_conversion.dart

import '../domain/entities/conversion_retry_result.dart';
import '../domain/entities/conversion_stage.dart';
import '../domain/entities/word_conversion_execution_result.dart';
import '../domain/entities/word_staging_result.dart';

typedef StageWordSourceRunner =
    Future<WordStagingResult> Function(int sourceFileId);

typedef ConvertStagedWordSourceRunner =
    Future<WordConversionExecutionResult> Function(
      int conversionId, {
      void Function(ConversionStage)? onStageChanged,
    });

/// Starts or retries a Word-to-PDF conversion from an operator-visible queue.
///
/// Pending conversions run the existing conversion row. Failed conversions are
/// restaged from their read-only source file, producing a fresh conversion row
/// while preserving the failed history.
class RetryWordConversion {
  const RetryWordConversion({
    required this.stageWordSource,
    required this.convertStagedWordSource,
  });

  final StageWordSourceRunner stageWordSource;
  final ConvertStagedWordSourceRunner convertStagedWordSource;

  Future<ConversionRetryResult> call({
    required int conversionId,
    required int sourceFileId,
    required String statusKey,
    void Function(ConversionStage)? onStageChanged,
  }) async {
    final int targetConversionId;
    if (statusKey == 'pending_conversion') {
      targetConversionId = conversionId;
    } else if (statusKey == 'conversion_failed') {
      final staging = await stageWordSource(sourceFileId);
      switch (staging) {
        case WordStagingSuccess(:final conversionId):
          targetConversionId = conversionId;
        case WordStagingAlreadyStaged(:final conversionId):
          targetConversionId = conversionId;
        case WordStagingBlocked() || WordStagingFailed():
          return const ConversionRetryBlocked();
      }
    } else {
      return const ConversionRetryBlocked();
    }

    final result = await convertStagedWordSource(
      targetConversionId,
      onStageChanged: onStageChanged,
    );
    return switch (result) {
      WordConversionExecutionSuccess() ||
      WordConversionAlreadyCompleted() => const ConversionRetrySucceeded(),
      WordConversionExecutionBlocked() => const ConversionRetryBlocked(),
      WordConversionExecutionFailed() => const ConversionRetryFailed(),
    };
  }
}
