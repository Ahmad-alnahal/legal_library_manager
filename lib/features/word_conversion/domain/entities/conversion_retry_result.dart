// lib/features/word_conversion/domain/entities/conversion_retry_result.dart

sealed class ConversionRetryResult {
  const ConversionRetryResult();
}

final class ConversionRetrySucceeded extends ConversionRetryResult {
  const ConversionRetrySucceeded();
}

final class ConversionRetryBlocked extends ConversionRetryResult {
  const ConversionRetryBlocked();
}

final class ConversionRetryFailed extends ConversionRetryResult {
  const ConversionRetryFailed();
}
