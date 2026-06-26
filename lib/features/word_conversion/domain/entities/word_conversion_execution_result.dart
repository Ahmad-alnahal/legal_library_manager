// lib/features/word_conversion/domain/entities/word_conversion_execution_result.dart

import 'word_conversion_execution_error.dart';

/// Structured result of the [ConvertStagedWordSource] use case.
sealed class WordConversionExecutionResult {
  const WordConversionExecutionResult();
}

/// Microsoft Word converted the staged source to PDF, the output was verified and
/// hashed, a `converted_pdf` document_files row was created, and the
/// `file_conversions` status is now `needs_conversion_review`.
final class WordConversionExecutionSuccess
    extends WordConversionExecutionResult {
  const WordConversionExecutionSuccess({
    required this.outputFileId,
    required this.outputPath,
    required this.pdfSha256,
  });

  /// ID of the newly inserted `converted_pdf` `document_files` row.
  final int outputFileId;

  /// Absolute path to the generated PDF in the app-owned output area.
  final String outputPath;

  /// SHA-256 hex digest of the generated PDF.
  final String pdfSha256;
}

/// The conversion is already in a completed state; no action was taken.
/// The caller may inspect [statusKey] to distinguish review-pending,
/// approved, and succeeded states.
final class WordConversionAlreadyCompleted
    extends WordConversionExecutionResult {
  const WordConversionAlreadyCompleted({required this.statusKey});

  final String statusKey;
}

/// A pre-flight check failed. The `file_conversions` row is unchanged (still
/// `pending_conversion` or `converting`) so a retry is possible once the
/// underlying condition is resolved.
final class WordConversionExecutionBlocked
    extends WordConversionExecutionResult {
  const WordConversionExecutionBlocked({
    required this.error,
    required this.safeMessage,
  });

  final WordConversionExecutionError error;
  final String safeMessage;
}

/// The conversion attempt failed after starting. The `file_conversions` row
/// has been updated to `conversion_failed`. The original source and staged
/// source are preserved unchanged.
final class WordConversionExecutionFailed
    extends WordConversionExecutionResult {
  const WordConversionExecutionFailed({
    required this.error,
    required this.safeMessage,
  });

  final WordConversionExecutionError error;
  final String safeMessage;
}
