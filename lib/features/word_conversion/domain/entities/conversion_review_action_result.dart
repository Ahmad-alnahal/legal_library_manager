// lib/features/word_conversion/domain/entities/conversion_review_action_result.dart

/// Result of an approve or reject review action.
sealed class ConversionReviewActionResult {
  const ConversionReviewActionResult();
}

/// The review decision was persisted successfully.
final class ConversionReviewActionSuccess extends ConversionReviewActionResult {
  const ConversionReviewActionSuccess();
}

/// The conversion was not in `needs_conversion_review` status (already decided
/// or not found). No change was made.
final class ConversionReviewActionNotReviewable
    extends ConversionReviewActionResult {
  const ConversionReviewActionNotReviewable();
}

/// A persistence or unexpected error prevented the decision from being saved.
final class ConversionReviewActionFailed extends ConversionReviewActionResult {
  const ConversionReviewActionFailed({required this.safeMessage});

  final String safeMessage;
}
