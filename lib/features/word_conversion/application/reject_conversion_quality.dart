// lib/features/word_conversion/application/reject_conversion_quality.dart

import '../../../core/time/clock.dart';
import '../domain/entities/conversion_review_action_result.dart';
import '../domain/repositories/word_conversion_repository.dart';

/// Rejects the quality of a converted PDF.
///
/// Sets `file_conversions.status_key` to `conversion_failed`, records
/// `quality_approved = false`, the review timestamp, and an optional safe
/// review note. The operation is atomic: it only succeeds when the current
/// status is exactly `needs_conversion_review`.
///
/// Neither the original Word source, its staged copy, nor the generated PDF
/// file on disk are deleted or modified by this use case.
class RejectConversionQuality {
  const RejectConversionQuality({
    required this._repository,
    required this._clock,
  });

  final WordConversionRepository _repository;
  final Clock _clock;

  /// [reviewNote] is optional safe text (no document contents). It is stored
  /// in `file_conversions.error_message_safe`.
  Future<ConversionReviewActionResult> call(
    int conversionId, {
    String? reviewNote,
  }) async {
    try {
      final nowIso = _clock.nowUtc().toIso8601String();
      final updated = await _repository.rejectConversionReview(
        conversionId: conversionId,
        nowIso: nowIso,
        reviewNote: reviewNote?.trim().isEmpty ?? true ? null : reviewNote,
      );
      if (!updated) return const ConversionReviewActionNotReviewable();
      return const ConversionReviewActionSuccess();
    } catch (_) {
      return const ConversionReviewActionFailed(
        safeMessage: 'could not persist the rejection decision',
      );
    }
  }
}
