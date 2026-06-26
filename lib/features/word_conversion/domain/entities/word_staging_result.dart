// lib/features/word_conversion/domain/entities/word_staging_result.dart

import 'word_staging_error.dart';

/// Structured result of a Word-source staging operation.
sealed class WordStagingResult {
  const WordStagingResult();
}

/// The source file was staged successfully. A `file_conversions` row with
/// `status_key = pending_conversion` now exists.
final class WordStagingSuccess extends WordStagingResult {
  const WordStagingSuccess({
    required this.stagedPath,
    required this.conversionId,
  });

  /// Absolute path to the staged Word file copy inside the app-owned staging area.
  final String stagedPath;

  /// ID of the newly created `file_conversions` row.
  final int conversionId;
}

/// A non-failed `file_conversions` row already exists for this source file.
/// Staging is idempotent; this outcome is safe and requires no further action.
final class WordStagingAlreadyStaged extends WordStagingResult {
  const WordStagingAlreadyStaged({
    required this.stagedPath,
    required this.conversionId,
  });

  final String stagedPath;
  final int conversionId;
}

/// A pre-flight check failed. No staging was attempted and no bytes were written.
final class WordStagingBlocked extends WordStagingResult {
  const WordStagingBlocked({required this.error, required this.safeMessage});

  final WordStagingError error;
  final String safeMessage;
}

/// The staging operation failed after starting. The original source file is
/// preserved unchanged.
final class WordStagingFailed extends WordStagingResult {
  const WordStagingFailed({required this.error, required this.safeMessage});

  final WordStagingError error;
  final String safeMessage;
}
