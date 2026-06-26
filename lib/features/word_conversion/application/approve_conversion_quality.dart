// lib/features/word_conversion/application/approve_conversion_quality.dart

import '../../../core/time/clock.dart';
import '../domain/entities/conversion_review_action_result.dart';
import '../domain/repositories/word_conversion_repository.dart';

/// Approves the quality of a converted PDF.
///
/// Sets `file_conversions.status_key` to `conversion_approved` and records the
/// review timestamp. The operation is atomic: it only succeeds when the current
/// status is exactly `needs_conversion_review`. Neither source files nor the
/// converted PDF file on disk are modified.
class ApproveConversionQuality {
  const ApproveConversionQuality({
    required this._repository,
    required this._clock,
  });

  final WordConversionRepository _repository;
  final Clock _clock;

  Future<ConversionReviewActionResult> call(int conversionId) async {
    try {
      final nowIso = _clock.nowUtc().toIso8601String();
      final updated = await _repository.approveConversionReview(
        conversionId: conversionId,
        nowIso: nowIso,
      );
      if (!updated) return const ConversionReviewActionNotReviewable();
      return const ConversionReviewActionSuccess();
    } catch (_) {
      return const ConversionReviewActionFailed(
        safeMessage: 'could not persist the approval decision',
      );
    }
  }
}
